# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tests/support/MIR4M4202PackageSuccession.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-MIR4M4202AssuranceRelease([bool]$Condition,[string]$Code,[string]$Detail=''){
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Assurance-Release-DecompositionV1.json'
$successorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Compatibility-Audit-DecompositionV1.json'
if(-not(Test-Path -LiteralPath $successorPath -PathType Leaf)){
  [void](& (Join-Path $repo 'tools/commands/mir4/Update-MIR4M4202AssuranceReleaseDecompositionAuthority.ps1') -RepoRoot $repo -Check)
}
$raw=Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4M4202AssuranceRelease ($raw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-assurance-release-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-release-schema'
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202AssuranceRelease (Test-MIR4BootstrapRecordHash -Record $receipt) 'mir4-m42-02-assurance-release-record'
$predecessorPath=Join-Path $repo ([string]$receipt.predecessor.receipt)
$predecessor=Get-Content -Raw -LiteralPath $predecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202AssuranceRelease ((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash-ceq[string]$receipt.predecessor.receipt_sha256-and[string]$predecessor.record_sha256-ceq[string]$receipt.predecessor.record_sha256) 'mir4-m42-02-assurance-release-predecessor'
$expectedInventoryDigest=[string]$receipt.tooling_inventory.digest
$expectedModuleSha=@{};foreach($module in @($receipt.decomposition.modules)){$expectedModuleSha[[string]$module.path]=[string]$module.sha256}
if(Test-Path -LiteralPath $successorPath -PathType Leaf){
  $successorRaw=Get-Content -Raw -LiteralPath $successorPath
  Assert-MIR4M4202AssuranceRelease ($successorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-compatibility-audit-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-release-successor-schema'
  $successor=$successorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202AssuranceRelease (Test-MIR4BootstrapRecordHash -Record $successor) 'mir4-m42-02-assurance-release-successor-record'
  Assert-MIR4M4202AssuranceRelease ((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash-ceq[string]$successor.predecessor.receipt_sha256-and[string]$receipt.record_sha256-ceq[string]$successor.predecessor.record_sha256) 'mir4-m42-02-assurance-release-successor-predecessor'
  foreach($binding in @($successor.evolved_bindings)){
    $path=[string]$binding.path
    if($expectedModuleSha.ContainsKey($path)){
      Assert-MIR4M4202AssuranceRelease ([string]$binding.previous_sha256-ceq[string]$expectedModuleSha[$path]) 'mir4-m42-02-assurance-release-successor-module-binding' $path
      $expectedModuleSha[$path]=[string]$binding.current_sha256
    }
  }
  $expectedInventoryDigest=[string]$successor.tooling_inventory.digest
  $offlineCustodySuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Offline-Custody-DecompositionV1.json'
  if(Test-Path -LiteralPath $offlineCustodySuccessorPath -PathType Leaf){
    $offlineCustodySuccessorRaw=Get-Content -Raw -LiteralPath $offlineCustodySuccessorPath
    Assert-MIR4M4202AssuranceRelease ($offlineCustodySuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-offline-custody-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-release-offline-custody-successor-schema'
    $offlineCustodySuccessor=$offlineCustodySuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR4M4202AssuranceRelease (Test-MIR4BootstrapRecordHash -Record $offlineCustodySuccessor) 'mir4-m42-02-assurance-release-offline-custody-successor-record'
    Assert-MIR4M4202AssuranceRelease ((Get-FileHash -LiteralPath $successorPath -Algorithm SHA256).Hash-ceq[string]$offlineCustodySuccessor.predecessor.receipt_sha256-and[string]$successor.record_sha256-ceq[string]$offlineCustodySuccessor.predecessor.record_sha256) 'mir4-m42-02-assurance-release-offline-custody-successor-predecessor'
    foreach($binding in @($offlineCustodySuccessor.evolved_bindings)){
      $path=[string]$binding.path
      if($expectedModuleSha.ContainsKey($path)){
        Assert-MIR4M4202AssuranceRelease ([string]$binding.previous_sha256-ceq[string]$expectedModuleSha[$path]) 'mir4-m42-02-assurance-release-offline-custody-successor-module-binding' $path
        $expectedModuleSha[$path]=[string]$binding.current_sha256
      }
    }
    $expectedInventoryDigest=[string]$offlineCustodySuccessor.tooling_inventory.digest
    $releaseCapsuleSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Release-Capsule-DecompositionV1.json'
    if(Test-Path -LiteralPath $releaseCapsuleSuccessorPath -PathType Leaf){
      $releaseCapsuleSuccessorRaw=Get-Content -Raw -LiteralPath $releaseCapsuleSuccessorPath
      Assert-MIR4M4202AssuranceRelease ($releaseCapsuleSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-release-capsule-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-release-release-capsule-successor-schema'
      $releaseCapsuleSuccessor=$releaseCapsuleSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
      Assert-MIR4M4202AssuranceRelease (Test-MIR4BootstrapRecordHash -Record $releaseCapsuleSuccessor) 'mir4-m42-02-assurance-release-release-capsule-successor-record'
      Assert-MIR4M4202AssuranceRelease ((Get-FileHash -LiteralPath $offlineCustodySuccessorPath -Algorithm SHA256).Hash-ceq[string]$releaseCapsuleSuccessor.predecessor.receipt_sha256-and[string]$offlineCustodySuccessor.record_sha256-ceq[string]$releaseCapsuleSuccessor.predecessor.record_sha256) 'mir4-m42-02-assurance-release-release-capsule-successor-predecessor'
      foreach($binding in @($releaseCapsuleSuccessor.evolved_bindings)){
        $path=[string]$binding.path
        if($expectedModuleSha.ContainsKey($path)){
          Assert-MIR4M4202AssuranceRelease ([string]$binding.previous_sha256-ceq[string]$expectedModuleSha[$path]) 'mir4-m42-02-assurance-release-release-capsule-successor-module-binding' $path
          $expectedModuleSha[$path]=[string]$binding.current_sha256
        }
      }
      $expectedInventoryDigest=[string]$releaseCapsuleSuccessor.tooling_inventory.digest
    }
  }
}

Assert-MIR4M4202AssuranceRelease (Update-MIR4M4202ExpectedBindingsThroughBridgeRetirement -RepoRoot $repo -ExpectedBindingSha $expectedModuleSha) 'mir4-m42-02-assurance-release-module-bridge-retirement-successor'
$functionNames=[Collections.Generic.List[string]]::new()
Assert-MIR4M4202AssuranceRelease (@($receipt.decomposition.modules).Count-eq4-and@($receipt.decomposition.modules|Group-Object path|Where-Object{$_.Count-ne1}).Count-eq0) 'mir4-m42-02-assurance-release-module-count'
foreach($module in @($receipt.decomposition.modules)){
  $path=Join-Path $repo ([string]$module.path);$tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
  Assert-MIR4M4202AssuranceRelease (@($errors).Count-eq0-and(Get-MIR4BootstrapTextSha256 -Path $path)-ceq[string]$expectedModuleSha[[string]$module.path]-and[int]$module.lines-le400) 'mir4-m42-02-assurance-release-module' ([string]$module.path)
  foreach($function in @($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true))){[void]$functionNames.Add($function.Name)}
}
$selfTestPath=Join-Path $repo ([string]$receipt.decomposition.self_test.path);$selfTokens=$null;$selfErrors=$null
$selfAst=[Management.Automation.Language.Parser]::ParseFile($selfTestPath,[ref]$selfTokens,[ref]$selfErrors)
$expectedSelfTestSha=@{([string]$receipt.decomposition.self_test.path)=[string]$receipt.decomposition.self_test.sha256}
Assert-MIR4M4202AssuranceRelease (Update-MIR4M4202ExpectedBindingsThroughBridgeRetirement -RepoRoot $repo -ExpectedBindingSha $expectedSelfTestSha) 'mir4-m42-02-assurance-release-self-test-bridge-retirement-successor'
Assert-MIR4M4202AssuranceRelease (@($selfErrors).Count-eq0-and(Get-MIR4BootstrapTextSha256 -Path $selfTestPath)-ceq[string]$expectedSelfTestSha[[string]$receipt.decomposition.self_test.path]-and@($selfAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count-eq1) 'mir4-m42-02-assurance-release-self-test'
foreach($function in @($selfAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true))){[void]$functionNames.Add($function.Name)}
$projectionSha=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $functionNames.ToArray())
Assert-MIR4M4202AssuranceRelease ($functionNames.Count-eq11-and$projectionSha-ceq[string]$receipt.public_contract.previous_sha256-and$projectionSha-ceq[string]$receipt.public_contract.current_sha256-and[bool]$receipt.public_contract.unchanged) 'mir4-m42-02-assurance-release-public-contract'

$facadePath=Join-Path $repo ([string]$receipt.decomposition.facade.path);$facadeTokens=$null;$facadeErrors=$null
$facadeAst=[Management.Automation.Language.Parser]::ParseFile($facadePath,[ref]$facadeTokens,[ref]$facadeErrors)
$facadeSource=Get-Content -Raw -LiteralPath $facadePath
Assert-MIR4M4202AssuranceRelease (@($facadeErrors).Count-eq0-and@($facadeAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count-eq0-and[int]$receipt.decomposition.facade.current_lines-le20) 'mir4-m42-02-assurance-release-facade'
Assert-MIR4M4202AssuranceRelease (-not$facadeSource.Contains('function Invoke-MIRAssuranceSelfTest')) 'mir4-m42-02-assurance-release-production-boundary'
$entrypointSource=Get-Content -Raw -LiteralPath (Join-Path $repo 'scripts/Invoke-MIRAssurance.ps1')
Assert-MIR4M4202AssuranceRelease ($entrypointSource.Contains('if ($command -ceq "self-test")')-and$entrypointSource.Contains('tests/tooling/support/MIRAssuranceSelfTest.ps1')) 'mir4-m42-02-assurance-release-self-test-route'

$controlExecutorSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Control-Executor-DecompositionV1.json'
if(Test-Path -LiteralPath $controlExecutorSuccessorPath -PathType Leaf){
  $controlExecutorSuccessorRaw=Get-Content -Raw -LiteralPath $controlExecutorSuccessorPath
  Assert-MIR4M4202AssuranceRelease ($controlExecutorSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-control-executor-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-release-control-executor-successor-schema'
  $controlExecutorSuccessor=$controlExecutorSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202AssuranceRelease (Test-MIR4BootstrapRecordHash -Record $controlExecutorSuccessor) 'mir4-m42-02-assurance-release-control-executor-successor-record'
  $controlExecutorPredecessorPath=Join-Path $repo ([string]$controlExecutorSuccessor.predecessor.receipt)
  $controlExecutorPredecessor=Get-Content -Raw -LiteralPath $controlExecutorPredecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202AssuranceRelease ((Get-FileHash -LiteralPath $controlExecutorPredecessorPath -Algorithm SHA256).Hash-ceq[string]$controlExecutorSuccessor.predecessor.receipt_sha256-and[string]$controlExecutorPredecessor.record_sha256-ceq[string]$controlExecutorSuccessor.predecessor.record_sha256) 'mir4-m42-02-assurance-release-control-executor-successor-predecessor'
  $expectedInventoryDigest=[string]$controlExecutorSuccessor.tooling_inventory.digest
}
$supplyChainSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Supply-Chain-DecompositionV1.json'
if(Test-Path -LiteralPath $supplyChainSuccessorPath -PathType Leaf){
  $supplyChainSuccessorRaw=Get-Content -Raw -LiteralPath $supplyChainSuccessorPath
  Assert-MIR4M4202AssuranceRelease ($supplyChainSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-supply-chain-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-release-supply-chain-successor-schema'
  $supplyChainSuccessor=$supplyChainSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202AssuranceRelease (Test-MIR4BootstrapRecordHash -Record $supplyChainSuccessor) 'mir4-m42-02-assurance-release-supply-chain-successor-record'
  $supplyChainPredecessorPath=Join-Path $repo ([string]$supplyChainSuccessor.predecessor.receipt)
  $supplyChainPredecessor=Get-Content -Raw -LiteralPath $supplyChainPredecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202AssuranceRelease ((Get-FileHash -LiteralPath $supplyChainPredecessorPath -Algorithm SHA256).Hash-ceq[string]$supplyChainSuccessor.predecessor.receipt_sha256-and[string]$supplyChainPredecessor.record_sha256-ceq[string]$supplyChainSuccessor.predecessor.record_sha256) 'mir4-m42-02-assurance-release-supply-chain-successor-predecessor'
  $expectedInventoryDigest=[string]$supplyChainSuccessor.tooling_inventory.digest
}

$expectedInventoryDigest=Get-MIR4M4202ExpectedInventoryDigestThroughBridgeRetirement -RepoRoot $repo -PredecessorDigest $expectedInventoryDigest
$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
Assert-MIR4M4202AssuranceRelease ([int]$inventory.command_count-eq85-and[int]$inventory.summary.unknown-eq0-and[int]$inventory.summary.duplicate_command_keys-eq0-and[string]$inventory.digest-ceq$expectedInventoryDigest) 'mir4-m42-02-assurance-release-inventory'
Assert-MIR4M4202AssuranceRelease ([bool]$receipt.semantic_contract.source_segments_exact-and[bool]$receipt.semantic_contract.candidate_planning_unchanged-and[bool]$receipt.semantic_contract.seal_creation_unchanged-and[bool]$receipt.semantic_contract.seal_verification_unchanged-and[bool]$receipt.semantic_contract.embedded_self_test_removed_from_release_authority) 'mir4-m42-02-assurance-release-semantic-contract'
Assert-MIR4M4202AssuranceRelease (@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-m42-02-assurance-release-transition'
Assert-MIR4M4202AssuranceRelease ((Test-MIR4M4202PackageSourceSuccession -RepoRoot $repo -PredecessorSha256 ([string]$receipt.preservation.package_source_sha256) -CurrentSha256 $packageBefore)-and@($receipt.preservation.package_visible_delta).Count-eq0-and(Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-m42-02-assurance-release-package-firewall'

[pscustomobject][ordered]@{
  status='M42-02-PS6-ASSURANCE-RELEASE-DECOMPOSITION-PASSED'
  facade_lines=[int]$receipt.decomposition.facade.current_lines
  production_modules=@($receipt.decomposition.modules).Count
  maximum_module_lines=(@($receipt.decomposition.modules|Measure-Object lines -Maximum).Maximum)
  production_functions=[int]$receipt.public_contract.production_function_count
  self_test_authority=[string]$receipt.decomposition.self_test.authority
  public_contract_sha256=$projectionSha
  package_source_sha256=$packageBefore
  package_visible=$false
  release_transition_authority=$false
}
