# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tests/support/MIR4M4202PackageSuccession.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-MIR4M4202SupplyChain {
  param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Diagnostic, [string]$Detail = '')
  if (-not $Condition) { throw "[$Diagnostic] $Detail".TrimEnd() }
}

$packageBefore = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$bridgeRetirementPath = Join-Path $repo 'releases/migrations/MIR4-M41-Current-Product-Bridge-RetirementV1.json'
if (-not (Test-Path -LiteralPath $bridgeRetirementPath -PathType Leaf)) {
  [void](& (Join-Path $repo 'tools/commands/mir4/Update-MIR4M4202SupplyChainDecompositionAuthority.ps1') -RepoRoot $repo -Check)
}
$receiptPath = Join-Path $repo 'releases/migrations/MIR4-M42-02-Supply-Chain-DecompositionV1.json'
$raw = Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4M4202SupplyChain ($raw | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-supply-chain-decomposition-v1.schema.json')) 'mir4-m42-02-supply-chain-schema'
$receipt = $raw | ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202SupplyChain (Test-MIR4BootstrapRecordHash -Record $receipt) 'mir4-m42-02-supply-chain-record'
$predecessorPath = Join-Path $repo ([string]$receipt.predecessor.receipt)
$predecessor = Get-Content -Raw -LiteralPath $predecessorPath | ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202SupplyChain ((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash -ceq [string]$receipt.predecessor.receipt_sha256 -and [string]$predecessor.record_sha256 -ceq [string]$receipt.predecessor.record_sha256) 'mir4-m42-02-supply-chain-predecessor'

$expectedModuleNames = @('CoreAndRows.ps1', 'ArchiveAndSelection.ps1', 'ComponentInventory.ps1', 'SpdxAttestation.ps1', 'ProvenanceAndVerification.ps1')
$functionNames = [Collections.Generic.List[string]]::new()
$actualModuleNames = @($receipt.decomposition.modules | ForEach-Object { Split-Path -Leaf ([string]$_.path) })
Assert-MIR4M4202SupplyChain (@($receipt.decomposition.modules).Count -eq 5 -and ($actualModuleNames -join '|') -ceq ($expectedModuleNames -join '|')) 'mir4-m42-02-supply-chain-module-order'
foreach ($module in @($receipt.decomposition.modules)) {
  $path = Join-Path $repo ([string]$module.path)
  $tokens = $null
  $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
  Assert-MIR4M4202SupplyChain (@($errors).Count -eq 0 -and (Get-MIR4BootstrapTextSha256 -Path $path) -ceq [string]$module.sha256 -and [int]$module.lines -le 400) 'mir4-m42-02-supply-chain-module' ([string]$module.path)
  foreach ($function in @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
    [void]$functionNames.Add($function.Name)
  }
}
$projectionSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $functionNames.ToArray())
Assert-MIR4M4202SupplyChain ($functionNames.Count -eq 28 -and $projectionSha -ceq [string]$receipt.public_contract.previous_function_sha256 -and $projectionSha -ceq [string]$receipt.public_contract.current_function_sha256 -and [bool]$receipt.public_contract.unchanged) 'mir4-m42-02-supply-chain-public-contract'

$facadePath = Join-Path $repo ([string]$receipt.decomposition.facade.path)
$facadeTokens = $null
$facadeErrors = $null
$facadeAst = [Management.Automation.Language.Parser]::ParseFile($facadePath, [ref]$facadeTokens, [ref]$facadeErrors)
$facadeSource = [IO.File]::ReadAllText($facadePath).Replace(([string][char]13 + [char]10), [string][char]10).Replace([string][char]13, [string][char]10)
$setupBlock = (@(Get-Content -LiteralPath $facadePath -TotalCount 11) -join [char]10) + [char]10
Assert-MIR4M4202SupplyChain (@($facadeErrors).Count -eq 0 -and @($facadeAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count -eq 0 -and [int]$receipt.decomposition.facade.current_lines -le 80) 'mir4-m42-02-supply-chain-facade'
Assert-MIR4M4202SupplyChain ((Get-MIR4Sha256String -Value $setupBlock) -ceq [string]$receipt.public_contract.setup_block_sha256) 'mir4-m42-02-supply-chain-setup'
foreach ($moduleName in $expectedModuleNames) {
  Assert-MIR4M4202SupplyChain ($facadeSource.Contains("supply-chain/$moduleName", [StringComparison]::Ordinal)) 'mir4-m42-02-supply-chain-facade-module' $moduleName
}

. $facadePath
Assert-MIR4M4202SupplyChain (Test-MIR4SupplyChainMapKey -Map @{alpha = 1} -Key 'alpha') 'mir4-m42-02-supply-chain-map-key-smoke'
Assert-MIR4M4202SupplyChain ((Get-MIR4SpdxElementToken -Value 'mir4-ps11') -cmatch '^[a-f0-9]{24}$') 'mir4-m42-02-supply-chain-spdx-token-smoke'
$inventory = Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
$expectedInventoryDigest = Get-MIR4M4202ExpectedInventoryDigestThroughBridgeRetirement -RepoRoot $repo -PredecessorDigest ([string]$receipt.tooling_inventory.digest)
Assert-MIR4M4202SupplyChain ([int]$inventory.command_count -eq 85 -and [int]$inventory.summary.unknown -eq 0 -and [int]$inventory.summary.duplicate_command_keys -eq 0 -and [string]$inventory.digest -ceq $expectedInventoryDigest) 'mir4-m42-02-supply-chain-inventory'
Assert-MIR4M4202SupplyChain ([bool]$receipt.semantic_contract.ordered_current_source_slices_preserved -and [bool]$receipt.semantic_contract.inventory_and_source_identity_unchanged -and [bool]$receipt.semantic_contract.archive_and_selection_unchanged -and [bool]$receipt.semantic_contract.component_inventory_unchanged -and [bool]$receipt.semantic_contract.spdx_attestation_unchanged -and [bool]$receipt.semantic_contract.slsa_provenance_unchanged -and [bool]$receipt.semantic_contract.policy_verification_unchanged -and [bool]$receipt.semantic_contract.custody_record_writing_unchanged -and [bool]$receipt.semantic_contract.platform_projections_regenerated -and [bool]$receipt.semantic_contract.powershell_decomposition_sequence_complete) 'mir4-m42-02-supply-chain-semantic-contract'
Assert-MIR4M4202SupplyChain ([string]$receipt.programme_transition.work_package -ceq 'M42-02' -and [string]$receipt.programme_transition.current_state -ceq 'complete' -and [string]$receipt.programme_transition.next_programme_state -ceq 'queued' -and [bool]$receipt.programme_transition.mir41_qualification_still_required) 'mir4-m42-02-supply-chain-programme-transition'
Assert-MIR4M4202SupplyChain (@($receipt.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-m42-02-supply-chain-transition'
Assert-MIR4M4202SupplyChain ((Test-MIR4M4202PackageSourceSuccession -RepoRoot $repo -PredecessorSha256 ([string]$receipt.preservation.package_source_sha256) -CurrentSha256 $packageBefore) -and @($receipt.preservation.package_visible_delta).Count -eq 0 -and (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-m42-02-supply-chain-package-firewall'

[pscustomobject][ordered]@{
  status = 'M42-02-PS11-SUPPLY-CHAIN-DECOMPOSITION-PASSED'
  facade_lines = [int]$receipt.decomposition.facade.current_lines
  modules = @($receipt.decomposition.modules).Count
  maximum_module_lines = (@($receipt.decomposition.modules | Measure-Object lines -Maximum).Maximum)
  functions = $functionNames.Count
  public_contract_sha256 = $projectionSha
  package_source_sha256 = $packageBefore
  package_visible = $false
  supply_chain_semantics_changed = $false
  powershell_decomposition_sequence_complete = $true
  mir41_qualification_still_required = $true
  release_transition_authority = $false
}
