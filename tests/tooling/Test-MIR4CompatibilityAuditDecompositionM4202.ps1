# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-MIR4M4202CompatibilityAudit {
  param([bool]$Condition, [string]$Code, [string]$Detail = '')
  if (-not $Condition) {
    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " $Detail" }
    throw "[$Code]$suffix"
  }
}

$packageBefore = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$successorPath = Join-Path $repo 'releases/migrations/MIR4-M42-02-Offline-Custody-DecompositionV1.json'
if (-not (Test-Path -LiteralPath $successorPath -PathType Leaf)) {
  [void](& (Join-Path $repo 'tools/commands/mir4/Update-MIR4M4202CompatibilityAuditDecompositionAuthority.ps1') -RepoRoot $repo -Check)
}
$receiptPath = Join-Path $repo 'releases/migrations/MIR4-M42-02-Compatibility-Audit-DecompositionV1.json'
$raw = Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4M4202CompatibilityAudit ($raw | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-compatibility-audit-decomposition-v1.schema.json')) 'mir4-m42-02-compatibility-audit-schema'
$receipt = $raw | ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202CompatibilityAudit (Test-MIR4BootstrapRecordHash -Record $receipt) 'mir4-m42-02-compatibility-audit-record'
$predecessorPath = Join-Path $repo ([string]$receipt.predecessor.receipt)
$predecessor = Get-Content -Raw -LiteralPath $predecessorPath | ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202CompatibilityAudit ((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash -ceq [string]$receipt.predecessor.receipt_sha256 -and [string]$predecessor.record_sha256 -ceq [string]$receipt.predecessor.record_sha256) 'mir4-m42-02-compatibility-audit-predecessor'

$expectedModuleNames = @('Configuration.ps1', 'InputDiscovery.ps1', 'ScenarioDefinitions.ps1', 'ScenarioResolution.ps1', 'ScenarioSelection.ps1', 'ResultCollation.ps1')
$functionNames = [Collections.Generic.List[string]]::new()
$actualModuleNames = @($receipt.decomposition.modules | ForEach-Object { Split-Path -Leaf ([string]$_.path) })
Assert-MIR4M4202CompatibilityAudit (@($receipt.decomposition.modules).Count -eq 6 -and ($actualModuleNames -join '|') -ceq ($expectedModuleNames -join '|')) 'mir4-m42-02-compatibility-audit-module-order'
foreach ($module in @($receipt.decomposition.modules)) {
  $path = Join-Path $repo ([string]$module.path)
  $tokens = $null
  $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
  Assert-MIR4M4202CompatibilityAudit (@($errors).Count -eq 0 -and (Get-MIR4BootstrapTextSha256 -Path $path) -ceq [string]$module.sha256 -and [int]$module.lines -le 400) 'mir4-m42-02-compatibility-audit-module' ([string]$module.path)
  foreach ($function in @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
    [void]$functionNames.Add($function.Name)
  }
}
$projectionSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $functionNames.ToArray())
Assert-MIR4M4202CompatibilityAudit ($functionNames.Count -eq 35 -and $projectionSha -ceq [string]$receipt.public_contract.previous_function_sha256 -and $projectionSha -ceq [string]$receipt.public_contract.current_function_sha256 -and [bool]$receipt.public_contract.unchanged) 'mir4-m42-02-compatibility-audit-public-contract'

$facadePath = Join-Path $repo ([string]$receipt.decomposition.facade.path)
$facadeTokens = $null
$facadeErrors = $null
$facadeAst = [Management.Automation.Language.Parser]::ParseFile($facadePath, [ref]$facadeTokens, [ref]$facadeErrors)
$facadeSource = [IO.File]::ReadAllText($facadePath).Replace(([string][char]13 + [char]10), [string][char]10).Replace([string][char]13, [string][char]10)
$parameterBlock = $facadeAst.ParamBlock.Extent.Text.Replace(([string][char]13 + [char]10), [string][char]10).Replace([string][char]13, [string][char]10) + [string][char]10
Assert-MIR4M4202CompatibilityAudit (@($facadeErrors).Count -eq 0 -and @($facadeAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count -eq 0 -and [int]$receipt.decomposition.facade.current_lines -le 80) 'mir4-m42-02-compatibility-audit-facade'
Assert-MIR4M4202CompatibilityAudit ((Get-MIR4Sha256String -Value $parameterBlock) -ceq [string]$receipt.public_contract.parameter_block_sha256 -and $facadeSource.Contains("$" + "compatAuditCommandRoot = $" + "PSScriptRoot", [StringComparison]::Ordinal)) 'mir4-m42-02-compatibility-audit-parameter-surface'

$probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('mir4-ps7-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $probeRoot | Out-Null
try {
  & $facadePath -Offline -MaxCandidates 0 -ModCacheDir (Join-Path $probeRoot 'cache') -OutputDir (Join-Path $probeRoot 'out')
  $report = Get-Content -Raw -LiteralPath (Join-Path $probeRoot 'out/compat-report.json') | ConvertFrom-Json -Depth 100
  Assert-MIR4M4202CompatibilityAudit ([int]$report.selected_count -eq 0 -and [int]$report.manual_selected_count -eq 0 -and [int]$report.generated_local_selected_count -eq 0 -and [int]$report.local_zip_selected_count -eq 0 -and [int]$report.mod_count -eq 0 -and [int]$report.failure_count -eq 0) 'mir4-m42-02-compatibility-audit-offline-smoke'
} finally {
  if (Test-Path -LiteralPath $probeRoot -PathType Container) {
    Remove-Item -LiteralPath $probeRoot -Recurse -Force
  }
}

$expectedInventoryDigest = [string]$receipt.tooling_inventory.digest
if (Test-Path -LiteralPath $successorPath -PathType Leaf) {
  $successorRaw = Get-Content -Raw -LiteralPath $successorPath
  Assert-MIR4M4202CompatibilityAudit ($successorRaw | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-offline-custody-decomposition-v1.schema.json')) 'mir4-m42-02-compatibility-audit-successor-schema'
  $successor = $successorRaw | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202CompatibilityAudit (Test-MIR4BootstrapRecordHash -Record $successor) 'mir4-m42-02-compatibility-audit-successor-record'
  Assert-MIR4M4202CompatibilityAudit ((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash -ceq [string]$successor.predecessor.receipt_sha256 -and [string]$receipt.record_sha256 -ceq [string]$successor.predecessor.record_sha256) 'mir4-m42-02-compatibility-audit-successor-predecessor'
  $expectedInventoryDigest = [string]$successor.tooling_inventory.digest
  $releaseCapsuleSuccessorPath = Join-Path $repo 'releases/migrations/MIR4-M42-02-Release-Capsule-DecompositionV1.json'
  if (Test-Path -LiteralPath $releaseCapsuleSuccessorPath -PathType Leaf) {
    $releaseCapsuleSuccessorRaw = Get-Content -Raw -LiteralPath $releaseCapsuleSuccessorPath
    Assert-MIR4M4202CompatibilityAudit ($releaseCapsuleSuccessorRaw | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-release-capsule-decomposition-v1.schema.json')) 'mir4-m42-02-compatibility-audit-release-capsule-successor-schema'
    $releaseCapsuleSuccessor = $releaseCapsuleSuccessorRaw | ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR4M4202CompatibilityAudit (Test-MIR4BootstrapRecordHash -Record $releaseCapsuleSuccessor) 'mir4-m42-02-compatibility-audit-release-capsule-successor-record'
    Assert-MIR4M4202CompatibilityAudit ((Get-FileHash -LiteralPath $successorPath -Algorithm SHA256).Hash -ceq [string]$releaseCapsuleSuccessor.predecessor.receipt_sha256 -and [string]$successor.record_sha256 -ceq [string]$releaseCapsuleSuccessor.predecessor.record_sha256) 'mir4-m42-02-compatibility-audit-release-capsule-successor-predecessor'
    $expectedInventoryDigest = [string]$releaseCapsuleSuccessor.tooling_inventory.digest
  }
}
$controlExecutorSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Control-Executor-DecompositionV1.json'
if(Test-Path -LiteralPath $controlExecutorSuccessorPath -PathType Leaf){
  $controlExecutorSuccessorRaw=Get-Content -Raw -LiteralPath $controlExecutorSuccessorPath
  Assert-MIR4M4202CompatibilityAudit ($controlExecutorSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-control-executor-decomposition-v1.schema.json')) 'mir4-m42-02-compatibility-audit-control-executor-successor-schema'
  $controlExecutorSuccessor=$controlExecutorSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202CompatibilityAudit (Test-MIR4BootstrapRecordHash -Record $controlExecutorSuccessor) 'mir4-m42-02-compatibility-audit-control-executor-successor-record'
  $controlExecutorPredecessorPath=Join-Path $repo ([string]$controlExecutorSuccessor.predecessor.receipt)
  $controlExecutorPredecessor=Get-Content -Raw -LiteralPath $controlExecutorPredecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202CompatibilityAudit ((Get-FileHash -LiteralPath $controlExecutorPredecessorPath -Algorithm SHA256).Hash-ceq[string]$controlExecutorSuccessor.predecessor.receipt_sha256-and[string]$controlExecutorPredecessor.record_sha256-ceq[string]$controlExecutorSuccessor.predecessor.record_sha256) 'mir4-m42-02-compatibility-audit-control-executor-successor-predecessor'
  $expectedInventoryDigest=[string]$controlExecutorSuccessor.tooling_inventory.digest
}
$supplyChainSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Supply-Chain-DecompositionV1.json'
if(Test-Path -LiteralPath $supplyChainSuccessorPath -PathType Leaf){
  $supplyChainSuccessorRaw=Get-Content -Raw -LiteralPath $supplyChainSuccessorPath
  Assert-MIR4M4202CompatibilityAudit ($supplyChainSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-supply-chain-decomposition-v1.schema.json')) 'mir4-m42-02-compatibility-audit-supply-chain-successor-schema'
  $supplyChainSuccessor=$supplyChainSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202CompatibilityAudit (Test-MIR4BootstrapRecordHash -Record $supplyChainSuccessor) 'mir4-m42-02-compatibility-audit-supply-chain-successor-record'
  $supplyChainPredecessorPath=Join-Path $repo ([string]$supplyChainSuccessor.predecessor.receipt)
  $supplyChainPredecessor=Get-Content -Raw -LiteralPath $supplyChainPredecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202CompatibilityAudit ((Get-FileHash -LiteralPath $supplyChainPredecessorPath -Algorithm SHA256).Hash-ceq[string]$supplyChainSuccessor.predecessor.receipt_sha256-and[string]$supplyChainPredecessor.record_sha256-ceq[string]$supplyChainSuccessor.predecessor.record_sha256) 'mir4-m42-02-compatibility-audit-supply-chain-successor-predecessor'
  $expectedInventoryDigest=[string]$supplyChainSuccessor.tooling_inventory.digest
}

$inventory = Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
Assert-MIR4M4202CompatibilityAudit ([int]$inventory.command_count -eq 85 -and [int]$inventory.summary.unknown -eq 0 -and [int]$inventory.summary.duplicate_command_keys -eq 0 -and [string]$inventory.digest -ceq $expectedInventoryDigest) 'mir4-m42-02-compatibility-audit-inventory'
Assert-MIR4M4202CompatibilityAudit ([bool]$receipt.semantic_contract.ordered_source_slices_preserved -and [bool]$receipt.semantic_contract.command_root_semantics_preserved -and [bool]$receipt.semantic_contract.parameter_surface_unchanged -and [bool]$receipt.semantic_contract.scenario_execution_unchanged -and [bool]$receipt.semantic_contract.result_collation_unchanged -and [bool]$receipt.semantic_contract.compatibility_claims_unchanged -and [bool]$receipt.semantic_contract.stream_authority_unchanged) 'mir4-m42-02-compatibility-audit-semantic-contract'
Assert-MIR4M4202CompatibilityAudit (@($receipt.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-m42-02-compatibility-audit-transition'
Assert-MIR4M4202CompatibilityAudit ([string]$receipt.preservation.package_source_sha256 -ceq $packageBefore -and @($receipt.preservation.package_visible_delta).Count -eq 0 -and (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-m42-02-compatibility-audit-package-firewall'

[pscustomobject][ordered]@{
  status = 'M42-02-PS7-COMPATIBILITY-AUDIT-DECOMPOSITION-PASSED'
  facade_lines = [int]$receipt.decomposition.facade.current_lines
  modules = @($receipt.decomposition.modules).Count
  maximum_module_lines = (@($receipt.decomposition.modules | Measure-Object lines -Maximum).Maximum)
  functions = $functionNames.Count
  public_contract_sha256 = $projectionSha
  package_source_sha256 = $packageBefore
  package_visible = $false
  compatibility_claims_changed = $false
  release_transition_authority = $false
}
