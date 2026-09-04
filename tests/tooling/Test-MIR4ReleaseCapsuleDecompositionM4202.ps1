# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-MIR4M4202ReleaseCapsule {
  param([bool]$Condition, [string]$Code, [string]$Detail = '')
  if (-not $Condition) {
    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " $Detail" }
    throw "[$Code]$suffix"
  }
}

$packageBefore = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$controlExecutorPath = Join-Path $repo 'releases/migrations/MIR4-M42-02-Control-Executor-DecompositionV1.json'
if (-not (Test-Path -LiteralPath $controlExecutorPath -PathType Leaf)) {
  [void](& (Join-Path $repo 'tools/commands/mir4/Update-MIR4M4202ReleaseCapsuleDecompositionAuthority.ps1') -RepoRoot $repo -Check)
}
$receiptPath = Join-Path $repo 'releases/migrations/MIR4-M42-02-Release-Capsule-DecompositionV1.json'
$raw = Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4M4202ReleaseCapsule ($raw | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-release-capsule-decomposition-v1.schema.json')) 'mir4-m42-02-release-capsule-schema'
$receipt = $raw | ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202ReleaseCapsule (Test-MIR4BootstrapRecordHash -Record $receipt) 'mir4-m42-02-release-capsule-record'
$predecessorPath = Join-Path $repo ([string]$receipt.predecessor.receipt)
$predecessor = Get-Content -Raw -LiteralPath $predecessorPath | ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202ReleaseCapsule ((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash -ceq [string]$receipt.predecessor.receipt_sha256 -and [string]$predecessor.record_sha256 -ceq [string]$receipt.predecessor.record_sha256) 'mir4-m42-02-release-capsule-predecessor'

$expectedModuleNames = @('CoreRecords.ps1', 'CustodyInventory.ps1', 'SourceArchiveAndDescriptors.ps1', 'SupportRecords.ps1', 'ArchiveReadingAndClosure.ps1', 'CapsuleConstruction.ps1', 'CapsuleVerification.ps1', 'CapsuleRestore.ps1')
$functionNames = [Collections.Generic.List[string]]::new()
$actualModuleNames = @($receipt.decomposition.modules | ForEach-Object { Split-Path -Leaf ([string]$_.path) })
Assert-MIR4M4202ReleaseCapsule (@($receipt.decomposition.modules).Count -eq 8 -and ($actualModuleNames -join '|') -ceq ($expectedModuleNames -join '|')) 'mir4-m42-02-release-capsule-module-order'
foreach ($module in @($receipt.decomposition.modules)) {
  $path = Join-Path $repo ([string]$module.path)
  $tokens = $null
  $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
  Assert-MIR4M4202ReleaseCapsule (@($errors).Count -eq 0 -and (Get-MIR4BootstrapTextSha256 -Path $path) -ceq [string]$module.sha256 -and [int]$module.lines -le 400) 'mir4-m42-02-release-capsule-module' ([string]$module.path)
  foreach ($function in @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
    [void]$functionNames.Add($function.Name)
  }
}
$projectionSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $functionNames.ToArray())
Assert-MIR4M4202ReleaseCapsule ($functionNames.Count -eq 19 -and $projectionSha -ceq [string]$receipt.public_contract.previous_function_sha256 -and $projectionSha -ceq [string]$receipt.public_contract.current_function_sha256 -and [bool]$receipt.public_contract.unchanged) 'mir4-m42-02-release-capsule-public-contract'

$facadePath = Join-Path $repo ([string]$receipt.decomposition.facade.path)
$facadeTokens = $null
$facadeErrors = $null
$facadeAst = [Management.Automation.Language.Parser]::ParseFile($facadePath, [ref]$facadeTokens, [ref]$facadeErrors)
$facadeSource = [IO.File]::ReadAllText($facadePath).Replace(([string][char]13 + [char]10), [string][char]10).Replace([string][char]13, [string][char]10)
$setupBlock = (@(Get-Content -LiteralPath $facadePath -TotalCount 18) -join [char]10) + [char]10
Assert-MIR4M4202ReleaseCapsule (@($facadeErrors).Count -eq 0 -and @($facadeAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count -eq 0 -and [int]$receipt.decomposition.facade.current_lines -le 80) 'mir4-m42-02-release-capsule-facade'
Assert-MIR4M4202ReleaseCapsule ((Get-MIR4Sha256String -Value $setupBlock) -ceq [string]$receipt.public_contract.setup_block_sha256) 'mir4-m42-02-release-capsule-setup'
foreach ($moduleName in $expectedModuleNames) {
  Assert-MIR4M4202ReleaseCapsule ($facadeSource.Contains("release-capsule/$moduleName", [StringComparison]::Ordinal)) 'mir4-m42-02-release-capsule-facade-module' $moduleName
}

. $facadePath
Assert-MIR4M4202ReleaseCapsule ((Get-MIR4ReleaseCapsuleRepoRootV1 -RepoRoot $repo) -ceq $repo) 'mir4-m42-02-release-capsule-repo-root-smoke'
$digest = 'A' * 64
Assert-MIR4M4202ReleaseCapsule ((Get-MIR4ReleaseCapsuleObjectPathV1 -Sha256 $digest) -ceq "objects/sha256/AA/$digest") 'mir4-m42-02-release-capsule-object-path-smoke'
$stream = [IO.MemoryStream]::new([byte[]](1, 2, 3, 4))
try {
  Assert-MIR4M4202ReleaseCapsule ((Get-MIR4ReleaseCapsuleStreamSha256V1 -Stream $stream) -ceq '9F64A747E1B97F131FABB6B447296C9B6F0201E79FB3C5356E6C77E89B6A806A') 'mir4-m42-02-release-capsule-stream-smoke'
} finally {
  $stream.Dispose()
}

$expectedInventoryDigest = [string]$receipt.tooling_inventory.digest
if (Test-Path -LiteralPath $controlExecutorPath -PathType Leaf) {
  $controlExecutorRaw = Get-Content -Raw -LiteralPath $controlExecutorPath
  Assert-MIR4M4202ReleaseCapsule ($controlExecutorRaw | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-control-executor-decomposition-v1.schema.json')) 'mir4-m42-02-release-capsule-control-executor-schema'
  $controlExecutor = $controlExecutorRaw | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202ReleaseCapsule (Test-MIR4BootstrapRecordHash -Record $controlExecutor) 'mir4-m42-02-release-capsule-control-executor-record'
  Assert-MIR4M4202ReleaseCapsule ((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash -ceq [string]$controlExecutor.predecessor.receipt_sha256 -and [string]$controlExecutor.predecessor.record_sha256 -ceq [string]$receipt.record_sha256) 'mir4-m42-02-release-capsule-control-executor-predecessor'
  Assert-MIR4M4202ReleaseCapsule ([string]$controlExecutor.current_source.sha256 -ceq '97EACF68C080CF9D38102A5BF26E96A42C015020F78DBA049461422E5673AF66' -and [bool]$controlExecutor.public_contract.unchanged -and [int]$controlExecutor.public_contract.function_count -eq 27) 'mir4-m42-02-release-capsule-control-executor-contract'
  $expectedInventoryDigest = [string]$controlExecutor.tooling_inventory.digest
}
$inventory = Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
Assert-MIR4M4202ReleaseCapsule ([int]$inventory.command_count -eq 85 -and [int]$inventory.summary.unknown -eq 0 -and [int]$inventory.summary.duplicate_command_keys -eq 0 -and [string]$inventory.digest -ceq $expectedInventoryDigest) 'mir4-m42-02-release-capsule-inventory'
Assert-MIR4M4202ReleaseCapsule ([bool]$receipt.semantic_contract.ordered_source_slices_preserved -and [bool]$receipt.semantic_contract.custody_inventory_unchanged -and [bool]$receipt.semantic_contract.source_archive_unchanged -and [bool]$receipt.semantic_contract.capsule_construction_unchanged -and [bool]$receipt.semantic_contract.capsule_verification_unchanged -and [bool]$receipt.semantic_contract.offline_restore_unchanged -and [bool]$receipt.semantic_contract.platform_projections_regenerated -and [bool]$receipt.semantic_contract.post_cutover_package_non_interference_assertion) 'mir4-m42-02-release-capsule-semantic-contract'
Assert-MIR4M4202ReleaseCapsule (@($receipt.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-m42-02-release-capsule-transition'
Assert-MIR4M4202ReleaseCapsule ([string]$receipt.preservation.package_source_sha256 -ceq $packageBefore -and @($receipt.preservation.package_visible_delta).Count -eq 0 -and (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-m42-02-release-capsule-package-firewall'

[pscustomobject][ordered]@{
  status = 'M42-02-PS9-RELEASE-CAPSULE-DECOMPOSITION-PASSED'
  facade_lines = [int]$receipt.decomposition.facade.current_lines
  modules = @($receipt.decomposition.modules).Count
  maximum_module_lines = (@($receipt.decomposition.modules | Measure-Object lines -Maximum).Maximum)
  functions = $functionNames.Count
  public_contract_sha256 = $projectionSha
  package_source_sha256 = $packageBefore
  package_visible = $false
  capsule_semantics_changed = $false
  release_transition_authority = $false
}
