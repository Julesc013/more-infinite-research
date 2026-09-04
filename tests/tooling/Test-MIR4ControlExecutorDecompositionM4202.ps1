# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-MIR4M4202ControlExecutor {
  param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Diagnostic, [string]$Detail = '')
  if (-not $Condition) { throw "[$Diagnostic] $Detail".TrimEnd() }
}

$packageBefore = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
[void](& (Join-Path $repo 'tools/commands/mir4/Update-MIR4M4202ControlExecutorDecompositionAuthority.ps1') -RepoRoot $repo -Check)
$receiptPath = Join-Path $repo 'releases/migrations/MIR4-M42-02-Control-Executor-DecompositionV1.json'
$raw = Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4M4202ControlExecutor ($raw | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-control-executor-decomposition-v1.schema.json')) 'mir4-m42-02-control-executor-schema'
$receipt = $raw | ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202ControlExecutor (Test-MIR4BootstrapRecordHash -Record $receipt) 'mir4-m42-02-control-executor-record'
$predecessorPath = Join-Path $repo ([string]$receipt.predecessor.receipt)
$predecessor = Get-Content -Raw -LiteralPath $predecessorPath | ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202ControlExecutor ((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash -ceq [string]$receipt.predecessor.receipt_sha256 -and [string]$predecessor.record_sha256 -ceq [string]$receipt.predecessor.record_sha256) 'mir4-m42-02-control-executor-predecessor'

$expectedModuleNames = @('ContextAndTaskExecution.ps1', 'EnvironmentExecution.ps1', 'PerformanceSourceAndArtifacts.ps1', 'RuntimeMeasurements.ps1', 'PackageDeltaMeasurements.ps1', 'AggregateGate.ps1')
$functionNames = [Collections.Generic.List[string]]::new()
$actualModuleNames = @($receipt.decomposition.modules | ForEach-Object { Split-Path -Leaf ([string]$_.path) })
Assert-MIR4M4202ControlExecutor (@($receipt.decomposition.modules).Count -eq 6 -and ($actualModuleNames -join '|') -ceq ($expectedModuleNames -join '|')) 'mir4-m42-02-control-executor-module-order'
foreach ($module in @($receipt.decomposition.modules)) {
  $path = Join-Path $repo ([string]$module.path)
  $tokens = $null
  $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
  Assert-MIR4M4202ControlExecutor (@($errors).Count -eq 0 -and (Get-MIR4BootstrapTextSha256 -Path $path) -ceq [string]$module.sha256 -and [int]$module.lines -le 400) 'mir4-m42-02-control-executor-module' ([string]$module.path)
  foreach ($function in @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
    [void]$functionNames.Add($function.Name)
  }
}
$projectionSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $functionNames.ToArray())
Assert-MIR4M4202ControlExecutor ($functionNames.Count -eq 27 -and $projectionSha -ceq [string]$receipt.public_contract.previous_function_sha256 -and $projectionSha -ceq [string]$receipt.public_contract.current_function_sha256 -and [bool]$receipt.public_contract.unchanged) 'mir4-m42-02-control-executor-public-contract'

$facadePath = Join-Path $repo ([string]$receipt.decomposition.facade.path)
$facadeTokens = $null
$facadeErrors = $null
$facadeAst = [Management.Automation.Language.Parser]::ParseFile($facadePath, [ref]$facadeTokens, [ref]$facadeErrors)
$facadeSource = [IO.File]::ReadAllText($facadePath).Replace(([string][char]13 + [char]10), [string][char]10).Replace([string][char]13, [string][char]10)
$setupBlock = (@(Get-Content -LiteralPath $facadePath -TotalCount 2) -join [char]10) + [char]10
Assert-MIR4M4202ControlExecutor (@($facadeErrors).Count -eq 0 -and @($facadeAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count -eq 0 -and [int]$receipt.decomposition.facade.current_lines -le 80) 'mir4-m42-02-control-executor-facade'
Assert-MIR4M4202ControlExecutor ((Get-MIR4Sha256String -Value $setupBlock) -ceq [string]$receipt.public_contract.setup_block_sha256) 'mir4-m42-02-control-executor-setup'
foreach ($moduleName in $expectedModuleNames) {
  Assert-MIR4M4202ControlExecutor ($facadeSource.Contains("executor/$moduleName", [StringComparison]::Ordinal)) 'mir4-m42-02-control-executor-facade-module' $moduleName
}

. $facadePath
Assert-MIR4M4202ControlExecutor (Test-MIRCPExactPathSet -Expected @('a', 'b') -Actual @('b', 'a')) 'mir4-m42-02-control-executor-path-set-smoke'
$inventory = Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
Assert-MIR4M4202ControlExecutor ([int]$inventory.command_count -eq 85 -and [int]$inventory.summary.unknown -eq 0 -and [int]$inventory.summary.duplicate_command_keys -eq 0 -and [string]$inventory.digest -ceq [string]$receipt.tooling_inventory.digest) 'mir4-m42-02-control-executor-inventory'
Assert-MIR4M4202ControlExecutor ([bool]$receipt.semantic_contract.ordered_current_source_slices_preserved -and [bool]$receipt.semantic_contract.context_execution_state_unchanged -and [bool]$receipt.semantic_contract.performance_source_and_artifact_custody_unchanged -and [bool]$receipt.semantic_contract.runtime_measurements_unchanged -and [bool]$receipt.semantic_contract.package_and_delta_measurements_unchanged -and [bool]$receipt.semantic_contract.aggregate_gate_unchanged -and [bool]$receipt.semantic_contract.ps7_source_evolution_preserved -and [bool]$receipt.semantic_contract.platform_projections_regenerated) 'mir4-m42-02-control-executor-semantic-contract'
Assert-MIR4M4202ControlExecutor (@($receipt.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-m42-02-control-executor-transition'
Assert-MIR4M4202ControlExecutor ([string]$receipt.preservation.package_source_sha256 -ceq $packageBefore -and @($receipt.preservation.package_visible_delta).Count -eq 0 -and (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-m42-02-control-executor-package-firewall'

[pscustomobject][ordered]@{
  status = 'M42-02-PS10-CONTROL-EXECUTOR-DECOMPOSITION-PASSED'
  facade_lines = [int]$receipt.decomposition.facade.current_lines
  modules = @($receipt.decomposition.modules).Count
  maximum_module_lines = (@($receipt.decomposition.modules | Measure-Object lines -Maximum).Maximum)
  functions = $functionNames.Count
  public_contract_sha256 = $projectionSha
  package_source_sha256 = $packageBefore
  package_visible = $false
  executor_semantics_changed = $false
  release_transition_authority = $false
}
