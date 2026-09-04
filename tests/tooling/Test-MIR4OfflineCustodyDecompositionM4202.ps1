# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-MIR4M4202OfflineCustody {
  param([bool]$Condition, [string]$Code, [string]$Detail = '')
  if (-not $Condition) {
    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " $Detail" }
    throw "[$Code]$suffix"
  }
}

$packageBefore = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$releaseCapsulePath = Join-Path $repo 'releases/migrations/MIR4-M42-02-Release-Capsule-DecompositionV1.json'
if (-not (Test-Path -LiteralPath $releaseCapsulePath -PathType Leaf)) {
  [void](& (Join-Path $repo 'tools/commands/mir4/Update-MIR4M4202OfflineCustodyDecompositionAuthority.ps1') -RepoRoot $repo -Check)
}
$receiptPath = Join-Path $repo 'releases/migrations/MIR4-M42-02-Offline-Custody-DecompositionV1.json'
$raw = Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4M4202OfflineCustody ($raw | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-offline-custody-decomposition-v1.schema.json')) 'mir4-m42-02-offline-custody-schema'
$receipt = $raw | ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202OfflineCustody (Test-MIR4BootstrapRecordHash -Record $receipt) 'mir4-m42-02-offline-custody-record'
$predecessorPath = Join-Path $repo ([string]$receipt.predecessor.receipt)
$predecessor = Get-Content -Raw -LiteralPath $predecessorPath | ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202OfflineCustody ((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash -ceq [string]$receipt.predecessor.receipt_sha256 -and [string]$predecessor.record_sha256 -ceq [string]$receipt.predecessor.record_sha256) 'mir4-m42-02-offline-custody-predecessor'

$expectedModuleNames = @('CoreRecords.ps1', 'Admission.ps1', 'SealInputs.ps1', 'OpenSshSignatures.ps1', 'ExactEngineEvidence.ps1', 'PublicationDryRun.ps1', 'OfflineSeal.ps1', 'RestoreAndCompletion.ps1')
$functionNames = [Collections.Generic.List[string]]::new()
$actualModuleNames = @($receipt.decomposition.modules | ForEach-Object { Split-Path -Leaf ([string]$_.path) })
Assert-MIR4M4202OfflineCustody (@($receipt.decomposition.modules).Count -eq 8 -and ($actualModuleNames -join '|') -ceq ($expectedModuleNames -join '|')) 'mir4-m42-02-offline-custody-module-order'
foreach ($module in @($receipt.decomposition.modules)) {
  $path = Join-Path $repo ([string]$module.path)
  $tokens = $null
  $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
  Assert-MIR4M4202OfflineCustody (@($errors).Count -eq 0 -and (Get-MIR4BootstrapTextSha256 -Path $path) -ceq [string]$module.sha256 -and [int]$module.lines -le 400) 'mir4-m42-02-offline-custody-module' ([string]$module.path)
  foreach ($function in @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
    [void]$functionNames.Add($function.Name)
  }
}
$projectionSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $functionNames.ToArray())
Assert-MIR4M4202OfflineCustody ($functionNames.Count -eq 26 -and $projectionSha -ceq [string]$receipt.public_contract.previous_function_sha256 -and $projectionSha -ceq [string]$receipt.public_contract.current_function_sha256 -and [bool]$receipt.public_contract.unchanged) 'mir4-m42-02-offline-custody-public-contract'

$facadePath = Join-Path $repo ([string]$receipt.decomposition.facade.path)
$facadeTokens = $null
$facadeErrors = $null
$facadeAst = [Management.Automation.Language.Parser]::ParseFile($facadePath, [ref]$facadeTokens, [ref]$facadeErrors)
$facadeSource = [IO.File]::ReadAllText($facadePath).Replace(([string][char]13 + [char]10), [string][char]10).Replace([string][char]13, [string][char]10)
$setupBlock = (@(Get-Content -LiteralPath $facadePath -TotalCount 25) -join [char]10) + [char]10
Assert-MIR4M4202OfflineCustody (@($facadeErrors).Count -eq 0 -and @($facadeAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count -eq 0 -and [int]$receipt.decomposition.facade.current_lines -le 80) 'mir4-m42-02-offline-custody-facade'
Assert-MIR4M4202OfflineCustody ((Get-MIR4Sha256String -Value $setupBlock) -ceq [string]$receipt.public_contract.setup_block_sha256 -and $facadeSource.Contains("$" + "script:MIR4OfflineCustodyApplicationRootV1 = $" + "PSScriptRoot", [StringComparison]::Ordinal)) 'mir4-m42-02-offline-custody-setup'
foreach ($moduleName in $expectedModuleNames) {
  Assert-MIR4M4202OfflineCustody ($facadeSource.Contains("offline-candidate-custody/$moduleName", [StringComparison]::Ordinal)) 'mir4-m42-02-offline-custody-facade-module' $moduleName
}

. $facadePath
$buildTests = Join-Path $repo 'build/tests'
$probeRoot = Join-Path $buildTests ('mir4-ps8-offline-custody-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $probeRoot | Out-Null
try {
  Assert-MIR4M4202OfflineCustody ((Get-MIR4CustodyRepoRootV1 -RepoRoot $repo) -ceq $repo) 'mir4-m42-02-offline-custody-repo-root'
  Assert-MIR4M4202OfflineCustody ((Get-MIR4CustodySchemaRootV1 -RepoRoot $repo) -ceq (Join-Path $repo 'spec/schemas')) 'mir4-m42-02-offline-custody-schema-root'
  $probePath = Join-Path $probeRoot 'record.json'
  $probe = [pscustomobject][ordered]@{schema=1;kind='MIR4OfflineCustodyPS8ProbeV1';canonicalization='MIR4BootstrapCanonicalJsonV1';status='synthetic-contract-probe';record_sha256=''}
  $probe = Write-MIR4CustodyRecordV1 -Record $probe -Path $probePath
  $binding = New-MIR4CustodyRecordBindingV1 -Role 'synthetic-contract-probe' -Record $probe -Path $probePath
  Assert-MIR4M4202OfflineCustody (Test-MIR4BootstrapRecordHash -Record $probe) 'mir4-m42-02-offline-custody-record-smoke'
  Assert-MIR4M4202OfflineCustody ([string]$binding.kind -ceq 'MIR4OfflineCustodyPS8ProbeV1' -and [string]$binding.record_sha256 -ceq [string]$probe.record_sha256 -and [string]$binding.file_sha256 -ceq (Get-MIR4Sha256File -Path $probePath)) 'mir4-m42-02-offline-custody-binding-smoke'
  Assert-MIR4M4202OfflineCustody (Test-MIR4CustodyDescendantPathV1 -Root $buildTests -Path $probePath) 'mir4-m42-02-offline-custody-containment-smoke'
  Assert-MIR4M4202OfflineCustody ((Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $probePath -Label 'PS8 contract probe') -ceq $probePath) 'mir4-m42-02-offline-custody-untracked-path-smoke'
  Assert-MIR4OfflineCustodyModeV1 -Mode 'dry-run' -Allowed 'dry-run'
  $rejected = $false
  try { Assert-MIR4OfflineCustodyModeV1 -Mode 'apply' -Allowed 'dry-run' } catch { $rejected = $true }
  Assert-MIR4M4202OfflineCustody $rejected 'mir4-m42-02-offline-custody-mode-smoke'
  $immutable = $false
  try { $null = Write-MIR4CustodyRecordV1 -Record $probe -Path $probePath } catch { $immutable = $true }
  Assert-MIR4M4202OfflineCustody $immutable 'mir4-m42-02-offline-custody-immutable-record-smoke'
} finally {
  if (Test-Path -LiteralPath $probeRoot -PathType Container) { Remove-MIR4BuildTree -OutputRoot $buildTests -Path $probeRoot }
}

$expectedInventoryDigest = [string]$receipt.tooling_inventory.digest
if (Test-Path -LiteralPath $releaseCapsulePath -PathType Leaf) {
  $releaseCapsuleRaw = Get-Content -Raw -LiteralPath $releaseCapsulePath
  Assert-MIR4M4202OfflineCustody ($releaseCapsuleRaw | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-release-capsule-decomposition-v1.schema.json')) 'mir4-m42-02-offline-custody-release-capsule-schema'
  $releaseCapsule = $releaseCapsuleRaw | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202OfflineCustody (Test-MIR4BootstrapRecordHash -Record $releaseCapsule) 'mir4-m42-02-offline-custody-release-capsule-record'
  Assert-MIR4M4202OfflineCustody ((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash -ceq [string]$releaseCapsule.predecessor.receipt_sha256 -and [string]$releaseCapsule.predecessor.record_sha256 -ceq [string]$receipt.record_sha256) 'mir4-m42-02-offline-custody-release-capsule-predecessor'
  Assert-MIR4M4202OfflineCustody ([string]$releaseCapsule.current_source.sha256 -ceq '6F35762B10F47084B71759E2A36B9163FF1B83CB336B325D67A48D426CCDB51D' -and [bool]$releaseCapsule.public_contract.unchanged -and [int]$releaseCapsule.public_contract.function_count -eq 19) 'mir4-m42-02-offline-custody-release-capsule-contract'
  $expectedInventoryDigest = [string]$releaseCapsule.tooling_inventory.digest
}
$controlExecutorSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Control-Executor-DecompositionV1.json'
if(Test-Path -LiteralPath $controlExecutorSuccessorPath -PathType Leaf){
  $controlExecutorSuccessorRaw=Get-Content -Raw -LiteralPath $controlExecutorSuccessorPath
  Assert-MIR4M4202OfflineCustody ($controlExecutorSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-control-executor-decomposition-v1.schema.json')) 'mir4-m42-02-offline-custody-control-executor-successor-schema'
  $controlExecutorSuccessor=$controlExecutorSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202OfflineCustody (Test-MIR4BootstrapRecordHash -Record $controlExecutorSuccessor) 'mir4-m42-02-offline-custody-control-executor-successor-record'
  $controlExecutorPredecessorPath=Join-Path $repo ([string]$controlExecutorSuccessor.predecessor.receipt)
  $controlExecutorPredecessor=Get-Content -Raw -LiteralPath $controlExecutorPredecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202OfflineCustody ((Get-FileHash -LiteralPath $controlExecutorPredecessorPath -Algorithm SHA256).Hash-ceq[string]$controlExecutorSuccessor.predecessor.receipt_sha256-and[string]$controlExecutorPredecessor.record_sha256-ceq[string]$controlExecutorSuccessor.predecessor.record_sha256) 'mir4-m42-02-offline-custody-control-executor-successor-predecessor'
  $expectedInventoryDigest=[string]$controlExecutorSuccessor.tooling_inventory.digest
}

$inventory = Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
Assert-MIR4M4202OfflineCustody ([int]$inventory.command_count -eq 85 -and [int]$inventory.summary.unknown -eq 0 -and [int]$inventory.summary.duplicate_command_keys -eq 0 -and [string]$inventory.digest -ceq $expectedInventoryDigest) 'mir4-m42-02-offline-custody-inventory'
Assert-MIR4M4202OfflineCustody ([bool]$receipt.semantic_contract.ordered_source_slices_preserved_with_declared_substitutions -and [bool]$receipt.semantic_contract.application_root_semantics_preserved -and [bool]$receipt.semantic_contract.setup_unchanged -and [bool]$receipt.semantic_contract.custody_admission_unchanged -and [bool]$receipt.semantic_contract.historical_compatibility_check_explicit -and [bool]$receipt.semantic_contract.seal_inputs_unchanged -and [bool]$receipt.semantic_contract.signature_verification_unchanged -and [bool]$receipt.semantic_contract.qualification_evidence_unchanged -and [bool]$receipt.semantic_contract.publication_dry_run_unchanged -and [bool]$receipt.semantic_contract.offline_seal_unchanged -and [bool]$receipt.semantic_contract.offline_restore_unchanged -and [bool]$receipt.semantic_contract.emergency_completion_unchanged) 'mir4-m42-02-offline-custody-semantic-contract'
Assert-MIR4M4202OfflineCustody (@($receipt.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-m42-02-offline-custody-transition'
Assert-MIR4M4202OfflineCustody ([string]$receipt.preservation.package_source_sha256 -ceq $packageBefore -and @($receipt.preservation.package_visible_delta).Count -eq 0 -and (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-m42-02-offline-custody-package-firewall'

[pscustomobject][ordered]@{
  status = 'M42-02-PS8-OFFLINE-CUSTODY-DECOMPOSITION-PASSED'
  facade_lines = [int]$receipt.decomposition.facade.current_lines
  modules = @($receipt.decomposition.modules).Count
  maximum_module_lines = (@($receipt.decomposition.modules | Measure-Object lines -Maximum).Maximum)
  functions = $functionNames.Count
  public_contract_sha256 = $projectionSha
  package_source_sha256 = $packageBefore
  package_visible = $false
  custody_semantics_changed = $false
  post_cutover_contract_smoke = $true
  release_transition_authority = $false
}
