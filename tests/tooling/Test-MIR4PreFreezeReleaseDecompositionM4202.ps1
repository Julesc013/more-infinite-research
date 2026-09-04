# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-MIR4PreFreezeReleaseDecompositionV1([bool]$Condition,[string]$Code,[string]$Detail=''){
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Pre-Freeze-Release-DecompositionV1.json'
$raw=Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4PreFreezeReleaseDecompositionV1 ($raw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-pre-freeze-release-decomposition-v1.schema.json')) 'mir4-m42-02-pre-freeze-release-schema'
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4PreFreezeReleaseDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $receipt) 'mir4-m42-02-pre-freeze-release-record'

$predecessorPath=Join-Path $repo ([string]$receipt.predecessor.receipt)
$predecessor=Get-Content -Raw -LiteralPath $predecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4PreFreezeReleaseDecompositionV1 ((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash-ceq[string]$receipt.predecessor.receipt_sha256-and[string]$predecessor.record_sha256-ceq[string]$receipt.predecessor.record_sha256) 'mir4-m42-02-pre-freeze-release-predecessor'
Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$receipt.status-ceq'M42-02-PS4-PRE-FREEZE-RELEASE-DECOMPOSED'-and[string]$receipt.next_fixed_point-ceq'M42-02-PS5-BOOTSTRAP-MATERIALIZATION') 'mir4-m42-02-pre-freeze-release-scope'
Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$receipt.characterization.sha256-ceq'1D21940B53412C4878B2E984C4C54F5BE81FDEC2FCD8E734D388FE8B966F2181'-and[string]$receipt.current_source.sha256-ceq'EF715051266F0984B7A57C1F61497E0FB614E2AB28F80EFE5A56D2350CB9C89E'-and[int]$receipt.current_source.lines-eq2283) 'mir4-m42-02-pre-freeze-release-source-chain'

$expectedInventoryDigest=[string]$receipt.tooling_inventory.digest
$expectedBindingSha=@{};foreach($binding in @($receipt.evolved_bindings)){$expectedBindingSha[[string]$binding.path]=[string]$binding.current_sha256}
$expectedModuleSha=@{};foreach($module in @($receipt.decomposition.modules)){$expectedModuleSha[[string]$module.path]=[string]$module.sha256}
$bootstrapSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Bootstrap-Materialization-DecompositionV1.json'
if(Test-Path -LiteralPath $bootstrapSuccessorPath -PathType Leaf){
  $bootstrapSuccessorRaw=Get-Content -Raw -LiteralPath $bootstrapSuccessorPath
  Assert-MIR4PreFreezeReleaseDecompositionV1 ($bootstrapSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-bootstrap-materialization-decomposition-v1.schema.json')) 'mir4-m42-02-pre-freeze-release-successor-schema'
  $bootstrapSuccessor=$bootstrapSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4PreFreezeReleaseDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $bootstrapSuccessor) 'mir4-m42-02-pre-freeze-release-successor-record'
  Assert-MIR4PreFreezeReleaseDecompositionV1 ((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash-ceq[string]$bootstrapSuccessor.predecessor.receipt_sha256-and[string]$receipt.record_sha256-ceq[string]$bootstrapSuccessor.predecessor.record_sha256) 'mir4-m42-02-pre-freeze-release-successor-predecessor'
  foreach($binding in @($bootstrapSuccessor.evolved_bindings)){
    $path=[string]$binding.path
    if($expectedBindingSha.ContainsKey($path)){
      Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-pre-freeze-release-successor-binding' $path
      $expectedBindingSha[$path]=[string]$binding.current_sha256
    }
    if($expectedModuleSha.ContainsKey($path)){
      Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedModuleSha[$path]) 'mir4-m42-02-pre-freeze-release-successor-module' $path
      $expectedModuleSha[$path]=[string]$binding.current_sha256
    }
  }
  $expectedInventoryDigest=[string]$bootstrapSuccessor.tooling_inventory.digest
  $assuranceReleaseSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Assurance-Release-DecompositionV1.json'
  if(Test-Path -LiteralPath $assuranceReleaseSuccessorPath -PathType Leaf){
    $assuranceReleaseSuccessorRaw=Get-Content -Raw -LiteralPath $assuranceReleaseSuccessorPath
    Assert-MIR4PreFreezeReleaseDecompositionV1 ($assuranceReleaseSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-assurance-release-decomposition-v1.schema.json')) 'mir4-m42-02-pre-freeze-release-assurance-release-successor-schema'
    $assuranceReleaseSuccessor=$assuranceReleaseSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR4PreFreezeReleaseDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $assuranceReleaseSuccessor) 'mir4-m42-02-pre-freeze-release-assurance-release-successor-record'
    Assert-MIR4PreFreezeReleaseDecompositionV1 ((Get-FileHash -LiteralPath $bootstrapSuccessorPath -Algorithm SHA256).Hash-ceq[string]$assuranceReleaseSuccessor.predecessor.receipt_sha256-and[string]$bootstrapSuccessor.record_sha256-ceq[string]$assuranceReleaseSuccessor.predecessor.record_sha256) 'mir4-m42-02-pre-freeze-release-assurance-release-successor-predecessor'
    foreach($binding in @($assuranceReleaseSuccessor.evolved_bindings)){
      $path=[string]$binding.path
      if($expectedBindingSha.ContainsKey($path)){
        Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-pre-freeze-release-assurance-release-successor-binding' $path
        $expectedBindingSha[$path]=[string]$binding.current_sha256
      }
      if($expectedModuleSha.ContainsKey($path)){
        Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedModuleSha[$path]) 'mir4-m42-02-pre-freeze-release-assurance-release-successor-module' $path
        $expectedModuleSha[$path]=[string]$binding.current_sha256
      }
    }
    $expectedInventoryDigest=[string]$assuranceReleaseSuccessor.tooling_inventory.digest
    $compatibilityAuditSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Compatibility-Audit-DecompositionV1.json'
    if(Test-Path -LiteralPath $compatibilityAuditSuccessorPath -PathType Leaf){
      $compatibilityAuditSuccessorRaw=Get-Content -Raw -LiteralPath $compatibilityAuditSuccessorPath
      Assert-MIR4PreFreezeReleaseDecompositionV1 ($compatibilityAuditSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-compatibility-audit-decomposition-v1.schema.json')) 'mir4-m42-02-pre-freeze-release-compatibility-audit-successor-schema'
      $compatibilityAuditSuccessor=$compatibilityAuditSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
      Assert-MIR4PreFreezeReleaseDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $compatibilityAuditSuccessor) 'mir4-m42-02-pre-freeze-release-compatibility-audit-successor-record'
      Assert-MIR4PreFreezeReleaseDecompositionV1 ((Get-FileHash -LiteralPath $assuranceReleaseSuccessorPath -Algorithm SHA256).Hash-ceq[string]$compatibilityAuditSuccessor.predecessor.receipt_sha256-and[string]$assuranceReleaseSuccessor.record_sha256-ceq[string]$compatibilityAuditSuccessor.predecessor.record_sha256) 'mir4-m42-02-pre-freeze-release-compatibility-audit-successor-predecessor'
      foreach($binding in @($compatibilityAuditSuccessor.evolved_bindings)){
        $path=[string]$binding.path
        if($expectedBindingSha.ContainsKey($path)){
          Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-pre-freeze-release-compatibility-audit-successor-binding' $path
          $expectedBindingSha[$path]=[string]$binding.current_sha256
        }
        if($expectedModuleSha.ContainsKey($path)){
          Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedModuleSha[$path]) 'mir4-m42-02-pre-freeze-release-compatibility-audit-successor-module' $path
          $expectedModuleSha[$path]=[string]$binding.current_sha256
        }
      }
      $expectedInventoryDigest=[string]$compatibilityAuditSuccessor.tooling_inventory.digest
      $offlineCustodySuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Offline-Custody-DecompositionV1.json'
      if(Test-Path -LiteralPath $offlineCustodySuccessorPath -PathType Leaf){
        $offlineCustodySuccessorRaw=Get-Content -Raw -LiteralPath $offlineCustodySuccessorPath
        Assert-MIR4PreFreezeReleaseDecompositionV1 ($offlineCustodySuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-offline-custody-decomposition-v1.schema.json')) 'mir4-m42-02-pre-freeze-release-offline-custody-successor-schema'
        $offlineCustodySuccessor=$offlineCustodySuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
        Assert-MIR4PreFreezeReleaseDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $offlineCustodySuccessor) 'mir4-m42-02-pre-freeze-release-offline-custody-successor-record'
        Assert-MIR4PreFreezeReleaseDecompositionV1 ((Get-FileHash -LiteralPath $compatibilityAuditSuccessorPath -Algorithm SHA256).Hash-ceq[string]$offlineCustodySuccessor.predecessor.receipt_sha256-and[string]$compatibilityAuditSuccessor.record_sha256-ceq[string]$offlineCustodySuccessor.predecessor.record_sha256) 'mir4-m42-02-pre-freeze-release-offline-custody-successor-predecessor'
        foreach($binding in @($offlineCustodySuccessor.evolved_bindings)){
          $path=[string]$binding.path
          if($expectedBindingSha.ContainsKey($path)){
            Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-pre-freeze-release-offline-custody-successor-binding' $path
            $expectedBindingSha[$path]=[string]$binding.current_sha256
          }
          if($expectedModuleSha.ContainsKey($path)){
            Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedModuleSha[$path]) 'mir4-m42-02-pre-freeze-release-offline-custody-successor-module' $path
            $expectedModuleSha[$path]=[string]$binding.current_sha256
          }
        }
        $expectedInventoryDigest=[string]$offlineCustodySuccessor.tooling_inventory.digest
        $releaseCapsuleSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Release-Capsule-DecompositionV1.json'
        if(Test-Path -LiteralPath $releaseCapsuleSuccessorPath -PathType Leaf){
          $releaseCapsuleSuccessorRaw=Get-Content -Raw -LiteralPath $releaseCapsuleSuccessorPath
          Assert-MIR4PreFreezeReleaseDecompositionV1 ($releaseCapsuleSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-release-capsule-decomposition-v1.schema.json')) 'mir4-m42-02-pre-freeze-release-release-capsule-successor-schema'
          $releaseCapsuleSuccessor=$releaseCapsuleSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
          Assert-MIR4PreFreezeReleaseDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $releaseCapsuleSuccessor) 'mir4-m42-02-pre-freeze-release-release-capsule-successor-record'
          Assert-MIR4PreFreezeReleaseDecompositionV1 ((Get-FileHash -LiteralPath $offlineCustodySuccessorPath -Algorithm SHA256).Hash-ceq[string]$releaseCapsuleSuccessor.predecessor.receipt_sha256-and[string]$offlineCustodySuccessor.record_sha256-ceq[string]$releaseCapsuleSuccessor.predecessor.record_sha256) 'mir4-m42-02-pre-freeze-release-release-capsule-successor-predecessor'
          foreach($binding in @($releaseCapsuleSuccessor.evolved_bindings)){
            $path=[string]$binding.path
            if($expectedBindingSha.ContainsKey($path)){
              Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-pre-freeze-release-release-capsule-successor-binding' $path
              $expectedBindingSha[$path]=[string]$binding.current_sha256
            }
            if($expectedModuleSha.ContainsKey($path)){
              Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedModuleSha[$path]) 'mir4-m42-02-pre-freeze-release-release-capsule-successor-module' $path
              $expectedModuleSha[$path]=[string]$binding.current_sha256
            }
          }
          $expectedInventoryDigest=[string]$releaseCapsuleSuccessor.tooling_inventory.digest
        }
      }
    }
  }
}

$controlExecutorModulePath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Control-Executor-DecompositionV1.json'
if(Test-Path -LiteralPath $controlExecutorModulePath -PathType Leaf){
  $controlExecutorModuleReceipt=Get-Content -Raw -LiteralPath $controlExecutorModulePath|ConvertFrom-Json -Depth 100 -DateKind String
  foreach($binding in @($controlExecutorModuleReceipt.evolved_bindings)){
    $path=[string]$binding.path
    if($expectedModuleSha.ContainsKey($path)){
      Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedModuleSha[$path]) 'mir4-m42-02-pre-freeze-release-control-executor-successor-module' $path
      $expectedModuleSha[$path]=[string]$binding.current_sha256
    }
  }
}
$supplyChainModulePath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Supply-Chain-DecompositionV1.json'
if(Test-Path -LiteralPath $supplyChainModulePath -PathType Leaf){
  $supplyChainModuleReceipt=Get-Content -Raw -LiteralPath $supplyChainModulePath|ConvertFrom-Json -Depth 100 -DateKind String
  foreach($binding in @($supplyChainModuleReceipt.evolved_bindings)){
    $path=[string]$binding.path
    if($expectedModuleSha.ContainsKey($path)){
      Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedModuleSha[$path]) 'mir4-m42-02-pre-freeze-release-supply-chain-successor-module' $path
      $expectedModuleSha[$path]=[string]$binding.current_sha256
    }
  }
}

$facadePath=Join-Path $repo ([string]$receipt.decomposition.facade.path)
$facadeTokens=$null;$facadeErrors=$null
$facadeAst=[Management.Automation.Language.Parser]::ParseFile($facadePath,[ref]$facadeTokens,[ref]$facadeErrors)
Assert-MIR4PreFreezeReleaseDecompositionV1 (@($facadeErrors).Count-eq0-and@($facadeAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count-eq0-and[int]$receipt.decomposition.facade.current_lines-le20) 'mir4-m42-02-pre-freeze-release-facade'
Assert-MIR4PreFreezeReleaseDecompositionV1 ((Get-MIR4BootstrapTextSha256 -Path $facadePath)-ceq[string]$receipt.decomposition.facade.current_sha256) 'mir4-m42-02-pre-freeze-release-facade-hash'

$functionNames=[Collections.Generic.List[string]]::new()
Assert-MIR4PreFreezeReleaseDecompositionV1 (@($receipt.decomposition.modules).Count-eq6-and@($receipt.decomposition.modules|Group-Object path|Where-Object{$_.Count-ne1}).Count-eq0) 'mir4-m42-02-pre-freeze-release-module-count'
foreach($module in @($receipt.decomposition.modules)){
  $path=Join-Path $repo ([string]$module.path);$tokens=$null;$parseErrors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
  Assert-MIR4PreFreezeReleaseDecompositionV1 (@($parseErrors).Count-eq0-and(Get-MIR4BootstrapTextSha256 -Path $path)-ceq[string]$expectedModuleSha[[string]$module.path]-and[int]$module.lines-le1000) 'mir4-m42-02-pre-freeze-release-module' ([string]$module.path)
  foreach($function in @($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true))){[void]$functionNames.Add($function.Name)}
}
$projectionSha=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $functionNames.ToArray())
Assert-MIR4PreFreezeReleaseDecompositionV1 ($functionNames.Count-eq25-and$projectionSha-ceq[string]$receipt.public_contract.previous_sha256-and$projectionSha-ceq[string]$receipt.public_contract.current_sha256-and[bool]$receipt.public_contract.unchanged) 'mir4-m42-02-pre-freeze-release-public-contract'

. $facadePath
foreach($requiredFunction in @('Get-MIR4PreFreezeAuthorityState','Test-MIR4PreFreezeAuthorities','Get-MIR4ReleaseDoctor','Test-MIR4ReleaseWorkflowInvocation','New-MIR4PlaytestSession','Complete-MIR4PlaytestSession')){
  Assert-MIR4PreFreezeReleaseDecompositionV1 ($null-ne(Get-Command $requiredFunction -CommandType Function -ErrorAction SilentlyContinue)) 'mir4-m42-02-pre-freeze-release-load' $requiredFunction
}
Assert-MIR4PreFreezeReleaseDecompositionV1 ([bool]$receipt.semantic_contract.source_segments_exact_except_declared_self_successor-and[bool]$receipt.semantic_contract.declared_self_successor_extension-and[bool]$receipt.semantic_contract.authority_locks_unchanged-and[bool]$receipt.semantic_contract.release_doctor_unchanged-and[bool]$receipt.semantic_contract.playtest_sessions_unchanged) 'mir4-m42-02-pre-freeze-release-semantic-contract'
$controlExecutorDigestPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Control-Executor-DecompositionV1.json'
if(Test-Path -LiteralPath $controlExecutorDigestPath -PathType Leaf){$expectedInventoryDigest=[string]((Get-Content -Raw -LiteralPath $controlExecutorDigestPath|ConvertFrom-Json -Depth 100 -DateKind String).tooling_inventory.digest)}
$supplyChainDigestPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Supply-Chain-DecompositionV1.json'
if(Test-Path -LiteralPath $supplyChainDigestPath -PathType Leaf){$expectedInventoryDigest=[string]((Get-Content -Raw -LiteralPath $supplyChainDigestPath|ConvertFrom-Json -Depth 100 -DateKind String).tooling_inventory.digest)}
$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
Assert-MIR4PreFreezeReleaseDecompositionV1 ([int]$inventory.command_count-eq85-and[int]$inventory.summary.unknown-eq0-and[int]$inventory.summary.duplicate_command_keys-eq0-and[string]$inventory.digest-ceq$expectedInventoryDigest) 'mir4-m42-02-pre-freeze-release-inventory'
$controlExecutorSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Control-Executor-DecompositionV1.json'
if(Test-Path -LiteralPath $controlExecutorSuccessorPath -PathType Leaf){
  $controlExecutorSuccessorRaw=Get-Content -Raw -LiteralPath $controlExecutorSuccessorPath
  Assert-MIR4PreFreezeReleaseDecompositionV1 ($controlExecutorSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-control-executor-decomposition-v1.schema.json')) 'mir4-m42-02-pre-freeze-release-control-executor-successor-schema'
  $controlExecutorSuccessor=$controlExecutorSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4PreFreezeReleaseDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $controlExecutorSuccessor) 'mir4-m42-02-pre-freeze-release-control-executor-successor-record'
  $controlExecutorPredecessorPath=Join-Path $repo ([string]$controlExecutorSuccessor.predecessor.receipt)
  $controlExecutorPredecessor=Get-Content -Raw -LiteralPath $controlExecutorPredecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4PreFreezeReleaseDecompositionV1 ((Get-FileHash -LiteralPath $controlExecutorPredecessorPath -Algorithm SHA256).Hash-ceq[string]$controlExecutorSuccessor.predecessor.receipt_sha256-and[string]$controlExecutorPredecessor.record_sha256-ceq[string]$controlExecutorSuccessor.predecessor.record_sha256) 'mir4-m42-02-pre-freeze-release-control-executor-successor-predecessor'
  foreach($binding in @($controlExecutorSuccessor.evolved_bindings)){
    $path=[string]$binding.path
    if($expectedBindingSha.ContainsKey($path)){
      Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-pre-freeze-release-control-executor-successor-binding' $path
      $expectedBindingSha[$path]=[string]$binding.current_sha256
    }
  }
  $expectedInventoryDigest=[string]$controlExecutorSuccessor.tooling_inventory.digest
}
$supplyChainSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Supply-Chain-DecompositionV1.json'
if(Test-Path -LiteralPath $supplyChainSuccessorPath -PathType Leaf){
  $supplyChainSuccessorRaw=Get-Content -Raw -LiteralPath $supplyChainSuccessorPath
  Assert-MIR4PreFreezeReleaseDecompositionV1 ($supplyChainSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-supply-chain-decomposition-v1.schema.json')) 'mir4-m42-02-pre-freeze-release-supply-chain-successor-schema'
  $supplyChainSuccessor=$supplyChainSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4PreFreezeReleaseDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $supplyChainSuccessor) 'mir4-m42-02-pre-freeze-release-supply-chain-successor-record'
  Assert-MIR4PreFreezeReleaseDecompositionV1 ((Get-FileHash -LiteralPath $controlExecutorSuccessorPath -Algorithm SHA256).Hash-ceq[string]$supplyChainSuccessor.predecessor.receipt_sha256-and[string]$controlExecutorSuccessor.record_sha256-ceq[string]$supplyChainSuccessor.predecessor.record_sha256) 'mir4-m42-02-pre-freeze-release-supply-chain-successor-predecessor'
  foreach($binding in @($supplyChainSuccessor.evolved_bindings)){
    $path=[string]$binding.path
    if($expectedBindingSha.ContainsKey($path)){
      Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-pre-freeze-release-supply-chain-successor-binding' $path
      $expectedBindingSha[$path]=[string]$binding.current_sha256
    }
  }
  $expectedInventoryDigest=[string]$supplyChainSuccessor.tooling_inventory.digest
}

foreach($binding in @($receipt.evolved_bindings)){
  Assert-MIR4PreFreezeReleaseDecompositionV1 ((Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo ([string]$binding.path)))-ceq[string]$expectedBindingSha[[string]$binding.path]-and-not[bool]$binding.package_visible-and-not[bool]$binding.release_authority) 'mir4-m42-02-pre-freeze-release-evolved-binding' ([string]$binding.path)
}
Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$receipt.preservation.package_source_sha256-ceq$packageBefore-and@($receipt.preservation.package_visible_delta).Count-eq0-and(Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-m42-02-pre-freeze-release-package-firewall'
Assert-MIR4PreFreezeReleaseDecompositionV1 (@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-m42-02-pre-freeze-release-release-firewall'

[pscustomobject][ordered]@{status='M42-02-PS4-PRE-FREEZE-RELEASE-DECOMPOSITION-PASSED';facade_lines=[int]$receipt.decomposition.facade.current_lines;modules=@($receipt.decomposition.modules).Count;maximum_module_lines=(@($receipt.decomposition.modules|Measure-Object lines -Maximum).Maximum);functions=$functionNames.Count;public_contract_sha256=$projectionSha;package_source_sha256=$packageBefore;package_visible=$false;release_transition_authority=$false}
