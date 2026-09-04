# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-MIR4AssuranceEvidenceDecompositionV1([bool]$Condition,[string]$Code,[string]$Detail=''){
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Assurance-Evidence-DecompositionV1.json'
$raw=Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4AssuranceEvidenceDecompositionV1 ($raw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-assurance-evidence-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-evidence-schema'
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4AssuranceEvidenceDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $receipt) 'mir4-m42-02-assurance-evidence-record'

$predecessorPath=Join-Path $repo ([string]$receipt.predecessor.receipt)
$predecessor=Get-Content -Raw -LiteralPath $predecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash-ceq[string]$receipt.predecessor.receipt_sha256-and[string]$predecessor.record_sha256-ceq[string]$receipt.predecessor.record_sha256) 'mir4-m42-02-assurance-evidence-predecessor'
Assert-MIR4AssuranceEvidenceDecompositionV1 ([string]$receipt.status-ceq'M42-02-PS3-ASSURANCE-EVIDENCE-DECOMPOSED'-and[string]$receipt.next_fixed_point-ceq'M42-02-PS4-PRE-FREEZE-RELEASE') 'mir4-m42-02-assurance-evidence-scope'

$facadePath=Join-Path $repo ([string]$receipt.decomposition.facade.path)
$facadeTokens=$null;$facadeErrors=$null
$facadeAst=[Management.Automation.Language.Parser]::ParseFile($facadePath,[ref]$facadeTokens,[ref]$facadeErrors)
Assert-MIR4AssuranceEvidenceDecompositionV1 (@($facadeErrors).Count-eq0-and@($facadeAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count-eq0-and[int]$receipt.decomposition.facade.current_lines-le20) 'mir4-m42-02-assurance-evidence-facade'
Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-MIR4BootstrapTextSha256 -Path $facadePath)-ceq[string]$receipt.decomposition.facade.current_sha256) 'mir4-m42-02-assurance-evidence-facade-hash'

$functionNames=[Collections.Generic.List[string]]::new()
Assert-MIR4AssuranceEvidenceDecompositionV1 (@($receipt.decomposition.modules).Count-eq9-and@($receipt.decomposition.modules|Group-Object path|Where-Object{$_.Count-ne1}).Count-eq0) 'mir4-m42-02-assurance-evidence-module-count'
foreach($module in @($receipt.decomposition.modules)){
  $path=Join-Path $repo ([string]$module.path)
  $tokens=$null;$parseErrors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
  Assert-MIR4AssuranceEvidenceDecompositionV1 (@($parseErrors).Count-eq0-and(Get-MIR4BootstrapTextSha256 -Path $path)-ceq[string]$module.sha256-and[int]$module.lines-le600) 'mir4-m42-02-assurance-evidence-module' ([string]$module.path)
  foreach($function in @($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true))){[void]$functionNames.Add($function.Name)}
}
$projectionSha=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $functionNames.ToArray())
Assert-MIR4AssuranceEvidenceDecompositionV1 ($functionNames.Count-eq62-and$projectionSha-ceq[string]$receipt.public_contract.previous_sha256-and$projectionSha-ceq[string]$receipt.public_contract.current_sha256-and[bool]$receipt.public_contract.unchanged) 'mir4-m42-02-assurance-evidence-public-contract'

$script:repo=$repo
. $facadePath
foreach($requiredFunction in @('Get-MIRAssuranceTestFingerprint','Test-MIRAssuranceTrustedProducer','Import-MIRAssuranceWorkerEvidence','Get-MIRAssuranceEvidenceDecision','Write-MIRAssuranceAttempt','Invoke-MIRAssuranceCommandText','Complete-MIRAssurancePlan','Invoke-MIRAssuranceGate')){
  Assert-MIR4AssuranceEvidenceDecompositionV1 ($null-ne(Get-Command $requiredFunction -CommandType Function -ErrorAction SilentlyContinue)) 'mir4-m42-02-assurance-evidence-load' $requiredFunction
}
Assert-MIR4AssuranceEvidenceDecompositionV1 ([bool]$receipt.semantic_contract.source_segments_exact-and[bool]$receipt.semantic_contract.fingerprints_unchanged-and[bool]$receipt.semantic_contract.producer_trust_unchanged-and[bool]$receipt.semantic_contract.worker_ingestion_unchanged-and[bool]$receipt.semantic_contract.plans_and_gates_unchanged) 'mir4-m42-02-assurance-evidence-semantic-contract'

$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
$expectedInventoryDigest=[string]$receipt.tooling_inventory.digest
$expectedBindingSha=@{}
foreach($binding in @($receipt.evolved_bindings)){$expectedBindingSha[[string]$binding.path]=[string]$binding.current_sha256}
$preFreezeSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Pre-Freeze-Release-DecompositionV1.json'
if(Test-Path -LiteralPath $preFreezeSuccessorPath -PathType Leaf){
  $preFreezeSuccessorRaw=Get-Content -Raw -LiteralPath $preFreezeSuccessorPath
  Assert-MIR4AssuranceEvidenceDecompositionV1 ($preFreezeSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-pre-freeze-release-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-evidence-successor-schema'
  $preFreezeSuccessor=$preFreezeSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4AssuranceEvidenceDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $preFreezeSuccessor) 'mir4-m42-02-assurance-evidence-successor-record'
  Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash-ceq[string]$preFreezeSuccessor.predecessor.receipt_sha256-and[string]$receipt.record_sha256-ceq[string]$preFreezeSuccessor.predecessor.record_sha256) 'mir4-m42-02-assurance-evidence-successor-predecessor'
  foreach($binding in @($preFreezeSuccessor.evolved_bindings)){
    $path=[string]$binding.path
    if($expectedBindingSha.ContainsKey($path)){
      Assert-MIR4AssuranceEvidenceDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-assurance-evidence-successor-binding' $path
      $expectedBindingSha[$path]=[string]$binding.current_sha256
    }
  }
  $expectedInventoryDigest=[string]$preFreezeSuccessor.tooling_inventory.digest
  $bootstrapMaterializationSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Bootstrap-Materialization-DecompositionV1.json'
  if(Test-Path -LiteralPath $bootstrapMaterializationSuccessorPath -PathType Leaf){
    $bootstrapMaterializationSuccessorRaw=Get-Content -Raw -LiteralPath $bootstrapMaterializationSuccessorPath
    Assert-MIR4AssuranceEvidenceDecompositionV1 ($bootstrapMaterializationSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-bootstrap-materialization-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-evidence-bootstrap-materialization-successor-schema'
    $bootstrapMaterializationSuccessor=$bootstrapMaterializationSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR4AssuranceEvidenceDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $bootstrapMaterializationSuccessor) 'mir4-m42-02-assurance-evidence-bootstrap-materialization-successor-record'
    Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-FileHash -LiteralPath $preFreezeSuccessorPath -Algorithm SHA256).Hash-ceq[string]$bootstrapMaterializationSuccessor.predecessor.receipt_sha256-and[string]$preFreezeSuccessor.record_sha256-ceq[string]$bootstrapMaterializationSuccessor.predecessor.record_sha256) 'mir4-m42-02-assurance-evidence-bootstrap-materialization-successor-predecessor'
    foreach($binding in @($bootstrapMaterializationSuccessor.evolved_bindings)){
      $path=[string]$binding.path
      if($expectedBindingSha.ContainsKey($path)){
        Assert-MIR4AssuranceEvidenceDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-assurance-evidence-bootstrap-materialization-successor-binding' $path
        $expectedBindingSha[$path]=[string]$binding.current_sha256
      }
    }
    $expectedInventoryDigest=[string]$bootstrapMaterializationSuccessor.tooling_inventory.digest
    $assuranceReleaseSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Assurance-Release-DecompositionV1.json'
    if(Test-Path -LiteralPath $assuranceReleaseSuccessorPath -PathType Leaf){
      $assuranceReleaseSuccessorRaw=Get-Content -Raw -LiteralPath $assuranceReleaseSuccessorPath
      Assert-MIR4AssuranceEvidenceDecompositionV1 ($assuranceReleaseSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-assurance-release-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-evidence-assurance-release-successor-schema'
      $assuranceReleaseSuccessor=$assuranceReleaseSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
      Assert-MIR4AssuranceEvidenceDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $assuranceReleaseSuccessor) 'mir4-m42-02-assurance-evidence-assurance-release-successor-record'
      Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-FileHash -LiteralPath $bootstrapMaterializationSuccessorPath -Algorithm SHA256).Hash-ceq[string]$assuranceReleaseSuccessor.predecessor.receipt_sha256-and[string]$bootstrapMaterializationSuccessor.record_sha256-ceq[string]$assuranceReleaseSuccessor.predecessor.record_sha256) 'mir4-m42-02-assurance-evidence-assurance-release-successor-predecessor'
      foreach($binding in @($assuranceReleaseSuccessor.evolved_bindings)){
        $path=[string]$binding.path
        if($expectedBindingSha.ContainsKey($path)){
          Assert-MIR4AssuranceEvidenceDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-assurance-evidence-assurance-release-successor-binding' $path
          $expectedBindingSha[$path]=[string]$binding.current_sha256
        }
      }
      $expectedInventoryDigest=[string]$assuranceReleaseSuccessor.tooling_inventory.digest
      $compatibilityAuditSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Compatibility-Audit-DecompositionV1.json'
      if(Test-Path -LiteralPath $compatibilityAuditSuccessorPath -PathType Leaf){
        $compatibilityAuditSuccessorRaw=Get-Content -Raw -LiteralPath $compatibilityAuditSuccessorPath
        Assert-MIR4AssuranceEvidenceDecompositionV1 ($compatibilityAuditSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-compatibility-audit-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-evidence-compatibility-audit-successor-schema'
        $compatibilityAuditSuccessor=$compatibilityAuditSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
        Assert-MIR4AssuranceEvidenceDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $compatibilityAuditSuccessor) 'mir4-m42-02-assurance-evidence-compatibility-audit-successor-record'
        Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-FileHash -LiteralPath $assuranceReleaseSuccessorPath -Algorithm SHA256).Hash-ceq[string]$compatibilityAuditSuccessor.predecessor.receipt_sha256-and[string]$assuranceReleaseSuccessor.record_sha256-ceq[string]$compatibilityAuditSuccessor.predecessor.record_sha256) 'mir4-m42-02-assurance-evidence-compatibility-audit-successor-predecessor'
        foreach($binding in @($compatibilityAuditSuccessor.evolved_bindings)){
          $path=[string]$binding.path
          if($expectedBindingSha.ContainsKey($path)){
            Assert-MIR4AssuranceEvidenceDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-assurance-evidence-compatibility-audit-successor-binding' $path
            $expectedBindingSha[$path]=[string]$binding.current_sha256
          }
        }
        $expectedInventoryDigest=[string]$compatibilityAuditSuccessor.tooling_inventory.digest
        $offlineCustodySuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Offline-Custody-DecompositionV1.json'
        if(Test-Path -LiteralPath $offlineCustodySuccessorPath -PathType Leaf){
          $offlineCustodySuccessorRaw=Get-Content -Raw -LiteralPath $offlineCustodySuccessorPath
          Assert-MIR4AssuranceEvidenceDecompositionV1 ($offlineCustodySuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-offline-custody-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-evidence-offline-custody-successor-schema'
          $offlineCustodySuccessor=$offlineCustodySuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
          Assert-MIR4AssuranceEvidenceDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $offlineCustodySuccessor) 'mir4-m42-02-assurance-evidence-offline-custody-successor-record'
          Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-FileHash -LiteralPath $compatibilityAuditSuccessorPath -Algorithm SHA256).Hash-ceq[string]$offlineCustodySuccessor.predecessor.receipt_sha256-and[string]$compatibilityAuditSuccessor.record_sha256-ceq[string]$offlineCustodySuccessor.predecessor.record_sha256) 'mir4-m42-02-assurance-evidence-offline-custody-successor-predecessor'
          foreach($binding in @($offlineCustodySuccessor.evolved_bindings)){
            $path=[string]$binding.path
            if($expectedBindingSha.ContainsKey($path)){
              Assert-MIR4AssuranceEvidenceDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-assurance-evidence-offline-custody-successor-binding' $path
              $expectedBindingSha[$path]=[string]$binding.current_sha256
            }
          }
          $expectedInventoryDigest=[string]$offlineCustodySuccessor.tooling_inventory.digest
          $releaseCapsuleSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Release-Capsule-DecompositionV1.json'
          if(Test-Path -LiteralPath $releaseCapsuleSuccessorPath -PathType Leaf){
            $releaseCapsuleSuccessorRaw=Get-Content -Raw -LiteralPath $releaseCapsuleSuccessorPath
            Assert-MIR4AssuranceEvidenceDecompositionV1 ($releaseCapsuleSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-release-capsule-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-evidence-release-capsule-successor-schema'
            $releaseCapsuleSuccessor=$releaseCapsuleSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
            Assert-MIR4AssuranceEvidenceDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $releaseCapsuleSuccessor) 'mir4-m42-02-assurance-evidence-release-capsule-successor-record'
            Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-FileHash -LiteralPath $offlineCustodySuccessorPath -Algorithm SHA256).Hash-ceq[string]$releaseCapsuleSuccessor.predecessor.receipt_sha256-and[string]$offlineCustodySuccessor.record_sha256-ceq[string]$releaseCapsuleSuccessor.predecessor.record_sha256) 'mir4-m42-02-assurance-evidence-release-capsule-successor-predecessor'
            foreach($binding in @($releaseCapsuleSuccessor.evolved_bindings)){
              $path=[string]$binding.path
              if($expectedBindingSha.ContainsKey($path)){
                Assert-MIR4AssuranceEvidenceDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-assurance-evidence-release-capsule-successor-binding' $path
                $expectedBindingSha[$path]=[string]$binding.current_sha256
              }
            }
            $expectedInventoryDigest=[string]$releaseCapsuleSuccessor.tooling_inventory.digest
          }
        }
      }
    }
  }
}
$controlExecutorDigestPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Control-Executor-DecompositionV1.json'
if(Test-Path -LiteralPath $controlExecutorDigestPath -PathType Leaf){$expectedInventoryDigest=[string]((Get-Content -Raw -LiteralPath $controlExecutorDigestPath|ConvertFrom-Json -Depth 100 -DateKind String).tooling_inventory.digest)}
$supplyChainDigestPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Supply-Chain-DecompositionV1.json'
if(Test-Path -LiteralPath $supplyChainDigestPath -PathType Leaf){$expectedInventoryDigest=[string]((Get-Content -Raw -LiteralPath $supplyChainDigestPath|ConvertFrom-Json -Depth 100 -DateKind String).tooling_inventory.digest)}
Assert-MIR4AssuranceEvidenceDecompositionV1 ([int]$inventory.command_count-eq85-and[int]$inventory.summary.unknown-eq0-and[int]$inventory.summary.duplicate_command_keys-eq0-and[string]$inventory.digest-ceq$expectedInventoryDigest) 'mir4-m42-02-assurance-evidence-inventory'
$controlExecutorSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Control-Executor-DecompositionV1.json'
if(Test-Path -LiteralPath $controlExecutorSuccessorPath -PathType Leaf){
  $controlExecutorSuccessorRaw=Get-Content -Raw -LiteralPath $controlExecutorSuccessorPath
  Assert-MIR4AssuranceEvidenceDecompositionV1 ($controlExecutorSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-control-executor-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-evidence-control-executor-successor-schema'
  $controlExecutorSuccessor=$controlExecutorSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4AssuranceEvidenceDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $controlExecutorSuccessor) 'mir4-m42-02-assurance-evidence-control-executor-successor-record'
  $controlExecutorPredecessorPath=Join-Path $repo ([string]$controlExecutorSuccessor.predecessor.receipt)
  $controlExecutorPredecessor=Get-Content -Raw -LiteralPath $controlExecutorPredecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-FileHash -LiteralPath $controlExecutorPredecessorPath -Algorithm SHA256).Hash-ceq[string]$controlExecutorSuccessor.predecessor.receipt_sha256-and[string]$controlExecutorPredecessor.record_sha256-ceq[string]$controlExecutorSuccessor.predecessor.record_sha256) 'mir4-m42-02-assurance-evidence-control-executor-successor-predecessor'
  foreach($binding in @($controlExecutorSuccessor.evolved_bindings)){
    $path=[string]$binding.path
    if($expectedBindingSha.ContainsKey($path)){
      Assert-MIR4AssuranceEvidenceDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-assurance-evidence-control-executor-successor-binding' $path
      $expectedBindingSha[$path]=[string]$binding.current_sha256
    }
  }
  $expectedInventoryDigest=[string]$controlExecutorSuccessor.tooling_inventory.digest
}
$supplyChainSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Supply-Chain-DecompositionV1.json'
if(Test-Path -LiteralPath $supplyChainSuccessorPath -PathType Leaf){
  $supplyChainSuccessorRaw=Get-Content -Raw -LiteralPath $supplyChainSuccessorPath
  Assert-MIR4AssuranceEvidenceDecompositionV1 ($supplyChainSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-supply-chain-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-evidence-supply-chain-successor-schema'
  $supplyChainSuccessor=$supplyChainSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4AssuranceEvidenceDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $supplyChainSuccessor) 'mir4-m42-02-assurance-evidence-supply-chain-successor-record'
  Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-FileHash -LiteralPath $controlExecutorSuccessorPath -Algorithm SHA256).Hash-ceq[string]$supplyChainSuccessor.predecessor.receipt_sha256-and[string]$controlExecutorSuccessor.record_sha256-ceq[string]$supplyChainSuccessor.predecessor.record_sha256) 'mir4-m42-02-assurance-evidence-supply-chain-successor-predecessor'
  foreach($binding in @($supplyChainSuccessor.evolved_bindings)){
    $path=[string]$binding.path
    if($expectedBindingSha.ContainsKey($path)){
      Assert-MIR4AssuranceEvidenceDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-assurance-evidence-supply-chain-successor-binding' $path
      $expectedBindingSha[$path]=[string]$binding.current_sha256
    }
  }
  $expectedInventoryDigest=[string]$supplyChainSuccessor.tooling_inventory.digest
}

foreach($binding in @($receipt.evolved_bindings)){
  Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo ([string]$binding.path)))-ceq[string]$expectedBindingSha[[string]$binding.path]-and-not[bool]$binding.package_visible-and-not[bool]$binding.release_authority) 'mir4-m42-02-assurance-evidence-evolved-binding' ([string]$binding.path)
}
Assert-MIR4AssuranceEvidenceDecompositionV1 ([string]$receipt.preservation.package_source_sha256-ceq$packageBefore-and@($receipt.preservation.package_visible_delta).Count-eq0) 'mir4-m42-02-assurance-evidence-package-firewall'
Assert-MIR4AssuranceEvidenceDecompositionV1 (@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-m42-02-assurance-evidence-release-firewall'
Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-m42-02-assurance-evidence-package-mutation'

[pscustomobject][ordered]@{
  status='M42-02-PS3-ASSURANCE-EVIDENCE-DECOMPOSITION-PASSED'
  facade_lines=[int]$receipt.decomposition.facade.current_lines
  modules=@($receipt.decomposition.modules).Count
  maximum_module_lines=(@($receipt.decomposition.modules|Measure-Object lines -Maximum).Maximum)
  functions=$functionNames.Count
  public_contract_sha256=$projectionSha
  package_source_sha256=$packageBefore
  package_visible=$false
  release_transition_authority=$false
}
