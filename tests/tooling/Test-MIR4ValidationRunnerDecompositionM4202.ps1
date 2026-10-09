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

function Assert-MIR4ValidationRunnerDecompositionV1([bool]$Condition,[string]$Code,[string]$Detail=''){
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Validation-Runner-DecompositionV1.json'
$assuranceSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Assurance-Evidence-DecompositionV1.json'
if(-not(Test-Path -LiteralPath $assuranceSuccessorPath -PathType Leaf)){
  [void](& (Join-Path $repo 'tools/commands/mir4/Update-MIR4M4202ValidationRunnerDecompositionAuthority.ps1') -RepoRoot $repo -Check)
}
$raw=Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4ValidationRunnerDecompositionV1 ($raw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-validation-runner-decomposition-v1.schema.json')) 'mir4-m42-02-validation-runner-schema'
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4ValidationRunnerDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $receipt) 'mir4-m42-02-validation-runner-record'

$predecessorPath=Join-Path $repo ([string]$receipt.predecessor.receipt)
$predecessor=Get-Content -Raw -LiteralPath $predecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4ValidationRunnerDecompositionV1 ((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash-ceq[string]$receipt.predecessor.receipt_sha256-and[string]$predecessor.record_sha256-ceq[string]$receipt.predecessor.record_sha256) 'mir4-m42-02-validation-runner-predecessor'
Assert-MIR4ValidationRunnerDecompositionV1 ([string]$receipt.status-ceq'M42-02-PS2-VALIDATION-RUNNER-DECOMPOSED'-and[string]$receipt.next_fixed_point-ceq'M42-02-PS3-ASSURANCE-EVIDENCE') 'mir4-m42-02-validation-runner-scope'

$facadePath=Join-Path $repo ([string]$receipt.decomposition.facade.path)
$facadeTokens=$null;$facadeErrors=$null
$facadeAst=[Management.Automation.Language.Parser]::ParseFile($facadePath,[ref]$facadeTokens,[ref]$facadeErrors)
$facadeLines=@([IO.File]::ReadAllLines($facadePath)).Count
$facadeParameters=$facadeAst.ParamBlock.Extent.Text.Replace("`r`n","`n").Replace("`r","`n")
Assert-MIR4ValidationRunnerDecompositionV1 (@($facadeErrors).Count-eq0-and$facadeAst.ParamBlock.Parameters.Count-eq[int]$receipt.public_contract.parameter_count-and$facadeLines-le[int]$receipt.decomposition.facade.maximum_lines) 'mir4-m42-02-validation-runner-facade'
Assert-MIR4ValidationRunnerDecompositionV1 ((Get-MIR4Sha256String -Value $facadeParameters)-ceq[string]$receipt.public_contract.current_sha256) 'mir4-m42-02-validation-runner-facade-public-contract'

$files=@($receipt.decomposition.modules)+@($receipt.decomposition.application)
Assert-MIR4ValidationRunnerDecompositionV1 (@($receipt.decomposition.modules).Count-eq21-and@($files|Group-Object path|Where-Object{$_.Count-ne1}).Count-eq0) 'mir4-m42-02-validation-runner-module-count'
$currentModuleLines=@()
$currentApplicationLines=0
foreach($file in $files){
  $path=Join-Path $repo ([string]$file.path)
  $tokens=$null;$parseErrors=$null
  $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
  Assert-MIR4ValidationRunnerDecompositionV1 (@($parseErrors).Count-eq0) 'mir4-m42-02-validation-runner-module-parse' ([string]$file.path)
  $lines=@([IO.File]::ReadAllLines($path)).Count
  if([string]$file.path-ceq[string]$receipt.decomposition.application.path){$currentApplicationLines=$lines}else{$currentModuleLines+=$lines}
}
Assert-MIR4ValidationRunnerDecompositionV1 (@($currentModuleLines|Where-Object{$_-gt[int]$receipt.decomposition.module_maximum_lines}).Count-eq0-and$currentApplicationLines-le[int]$receipt.decomposition.application.maximum_lines) 'mir4-m42-02-validation-runner-bounds'

Assert-MIR4ValidationRunnerDecompositionV1 ([bool]$receipt.public_contract.unchanged-and[string]$receipt.public_contract.previous_sha256-ceq[string]$receipt.public_contract.current_sha256) 'mir4-m42-02-validation-runner-public-contract'
Assert-MIR4ValidationRunnerDecompositionV1 ([bool]$receipt.semantic_contract.source_segments_exact-and[bool]$receipt.semantic_contract.scenario_names_and_groups_unchanged-and[bool]$receipt.semantic_contract.schema_2_result_contract_unchanged) 'mir4-m42-02-validation-runner-semantic-contract'
Assert-MIR4ValidationRunnerDecompositionV1 ([int]$receipt.semantic_contract.runtime_registry.profile_counts.f210-eq135-and[int]$receipt.semantic_contract.runtime_registry.profile_counts.f200-eq7-and[int]$receipt.semantic_contract.runtime_registry.profile_counts.f110-eq4-and[int]$receipt.semantic_contract.runtime_registry.profile_counts.f100-eq4) 'mir4-m42-02-validation-runner-target-counts'
Assert-MIR4ValidationRunnerDecompositionV1 (Test-MIR4M4202HistoricalValidationRunnerDecomposition -RepoRoot $repo -Receipt $receipt) 'mir4-m42-02-validation-runner-historical-reconstruction'

$listOutput=(& pwsh -NoProfile -File $facadePath -List 2>&1|Out-String)
Assert-MIR4ValidationRunnerDecompositionV1 ($LASTEXITCODE-eq0-and$listOutput-match'package-zip-base'-and$listOutput-match'static-validation'-and$listOutput-notmatch'\[check\] info.json parses') 'mir4-m42-02-validation-runner-list-mode'
$docsOutput=(& pwsh -NoProfile -File $facadePath -DocsOnly 2>&1|Out-String)
Assert-MIR4ValidationRunnerDecompositionV1 ($LASTEXITCODE-eq0-and$docsOutput-match'MIR docs and governance lint passed'-and$docsOutput-notmatch'\[check\] info.json parses') 'mir4-m42-02-validation-runner-docs-mode'

$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
$expectedBindingSha=@{}
foreach($binding in @($receipt.evolved_bindings)){$expectedBindingSha[[string]$binding.path]=[string]$binding.current_sha256}
if(Test-Path -LiteralPath $assuranceSuccessorPath -PathType Leaf){
  $assuranceSuccessorRaw=Get-Content -Raw -LiteralPath $assuranceSuccessorPath
  Assert-MIR4ValidationRunnerDecompositionV1 ($assuranceSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-assurance-evidence-decomposition-v1.schema.json')) 'mir4-m42-02-validation-runner-successor-schema'
  $assuranceSuccessor=$assuranceSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4ValidationRunnerDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $assuranceSuccessor) 'mir4-m42-02-validation-runner-successor-record'
  Assert-MIR4ValidationRunnerDecompositionV1 ((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash-ceq[string]$assuranceSuccessor.predecessor.receipt_sha256-and[string]$receipt.record_sha256-ceq[string]$assuranceSuccessor.predecessor.record_sha256) 'mir4-m42-02-validation-runner-successor-predecessor'
  foreach($binding in @($assuranceSuccessor.evolved_bindings)){
    $path=[string]$binding.path
    if($expectedBindingSha.ContainsKey($path)){
      Assert-MIR4ValidationRunnerDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-validation-runner-successor-binding' $path
      $expectedBindingSha[$path]=[string]$binding.current_sha256
    }
  }
  $preFreezeSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Pre-Freeze-Release-DecompositionV1.json'
  if(Test-Path -LiteralPath $preFreezeSuccessorPath -PathType Leaf){
    $preFreezeSuccessorRaw=Get-Content -Raw -LiteralPath $preFreezeSuccessorPath
    Assert-MIR4ValidationRunnerDecompositionV1 ($preFreezeSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-pre-freeze-release-decomposition-v1.schema.json')) 'mir4-m42-02-validation-runner-pre-freeze-successor-schema'
    $preFreezeSuccessor=$preFreezeSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR4ValidationRunnerDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $preFreezeSuccessor) 'mir4-m42-02-validation-runner-pre-freeze-successor-record'
    Assert-MIR4ValidationRunnerDecompositionV1 ((Get-FileHash -LiteralPath $assuranceSuccessorPath -Algorithm SHA256).Hash-ceq[string]$preFreezeSuccessor.predecessor.receipt_sha256-and[string]$assuranceSuccessor.record_sha256-ceq[string]$preFreezeSuccessor.predecessor.record_sha256) 'mir4-m42-02-validation-runner-pre-freeze-successor-predecessor'
    foreach($binding in @($preFreezeSuccessor.evolved_bindings)){
      $path=[string]$binding.path
      if($expectedBindingSha.ContainsKey($path)){
        Assert-MIR4ValidationRunnerDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-validation-runner-pre-freeze-successor-binding' $path
        $expectedBindingSha[$path]=[string]$binding.current_sha256
      }
    }
    $bootstrapMaterializationSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Bootstrap-Materialization-DecompositionV1.json'
    if(Test-Path -LiteralPath $bootstrapMaterializationSuccessorPath -PathType Leaf){
      $bootstrapMaterializationSuccessorRaw=Get-Content -Raw -LiteralPath $bootstrapMaterializationSuccessorPath
      Assert-MIR4ValidationRunnerDecompositionV1 ($bootstrapMaterializationSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-bootstrap-materialization-decomposition-v1.schema.json')) 'mir4-m42-02-validation-runner-bootstrap-materialization-successor-schema'
      $bootstrapMaterializationSuccessor=$bootstrapMaterializationSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
      Assert-MIR4ValidationRunnerDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $bootstrapMaterializationSuccessor) 'mir4-m42-02-validation-runner-bootstrap-materialization-successor-record'
      Assert-MIR4ValidationRunnerDecompositionV1 ((Get-FileHash -LiteralPath $preFreezeSuccessorPath -Algorithm SHA256).Hash-ceq[string]$bootstrapMaterializationSuccessor.predecessor.receipt_sha256-and[string]$preFreezeSuccessor.record_sha256-ceq[string]$bootstrapMaterializationSuccessor.predecessor.record_sha256) 'mir4-m42-02-validation-runner-bootstrap-materialization-successor-predecessor'
      foreach($binding in @($bootstrapMaterializationSuccessor.evolved_bindings)){
        $path=[string]$binding.path
        if($expectedBindingSha.ContainsKey($path)){
          Assert-MIR4ValidationRunnerDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-validation-runner-bootstrap-materialization-successor-binding' $path
          $expectedBindingSha[$path]=[string]$binding.current_sha256
        }
      }
      $assuranceReleaseSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Assurance-Release-DecompositionV1.json'
      if(Test-Path -LiteralPath $assuranceReleaseSuccessorPath -PathType Leaf){
        $assuranceReleaseSuccessorRaw=Get-Content -Raw -LiteralPath $assuranceReleaseSuccessorPath
        Assert-MIR4ValidationRunnerDecompositionV1 ($assuranceReleaseSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-assurance-release-decomposition-v1.schema.json')) 'mir4-m42-02-validation-runner-assurance-release-successor-schema'
        $assuranceReleaseSuccessor=$assuranceReleaseSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
        Assert-MIR4ValidationRunnerDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $assuranceReleaseSuccessor) 'mir4-m42-02-validation-runner-assurance-release-successor-record'
        Assert-MIR4ValidationRunnerDecompositionV1 ((Get-FileHash -LiteralPath $bootstrapMaterializationSuccessorPath -Algorithm SHA256).Hash-ceq[string]$assuranceReleaseSuccessor.predecessor.receipt_sha256-and[string]$bootstrapMaterializationSuccessor.record_sha256-ceq[string]$assuranceReleaseSuccessor.predecessor.record_sha256) 'mir4-m42-02-validation-runner-assurance-release-successor-predecessor'
        foreach($binding in @($assuranceReleaseSuccessor.evolved_bindings)){
          $path=[string]$binding.path
          if($expectedBindingSha.ContainsKey($path)){
            Assert-MIR4ValidationRunnerDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-validation-runner-assurance-release-successor-binding' $path
            $expectedBindingSha[$path]=[string]$binding.current_sha256
          }
        }
        $compatibilityAuditSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Compatibility-Audit-DecompositionV1.json'
        if(Test-Path -LiteralPath $compatibilityAuditSuccessorPath -PathType Leaf){
          $compatibilityAuditSuccessorRaw=Get-Content -Raw -LiteralPath $compatibilityAuditSuccessorPath
          Assert-MIR4ValidationRunnerDecompositionV1 ($compatibilityAuditSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-compatibility-audit-decomposition-v1.schema.json')) 'mir4-m42-02-validation-runner-compatibility-audit-successor-schema'
          $compatibilityAuditSuccessor=$compatibilityAuditSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
          Assert-MIR4ValidationRunnerDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $compatibilityAuditSuccessor) 'mir4-m42-02-validation-runner-compatibility-audit-successor-record'
          Assert-MIR4ValidationRunnerDecompositionV1 ((Get-FileHash -LiteralPath $assuranceReleaseSuccessorPath -Algorithm SHA256).Hash-ceq[string]$compatibilityAuditSuccessor.predecessor.receipt_sha256-and[string]$assuranceReleaseSuccessor.record_sha256-ceq[string]$compatibilityAuditSuccessor.predecessor.record_sha256) 'mir4-m42-02-validation-runner-compatibility-audit-successor-predecessor'
          foreach($binding in @($compatibilityAuditSuccessor.evolved_bindings)){
            $path=[string]$binding.path
              if($expectedBindingSha.ContainsKey($path)){
                Assert-MIR4ValidationRunnerDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-validation-runner-compatibility-audit-successor-binding' $path
                $expectedBindingSha[$path]=[string]$binding.current_sha256
              }
          }
          $offlineCustodySuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Offline-Custody-DecompositionV1.json'
          if(Test-Path -LiteralPath $offlineCustodySuccessorPath -PathType Leaf){
            $offlineCustodySuccessorRaw=Get-Content -Raw -LiteralPath $offlineCustodySuccessorPath
            Assert-MIR4ValidationRunnerDecompositionV1 ($offlineCustodySuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-offline-custody-decomposition-v1.schema.json')) 'mir4-m42-02-validation-runner-offline-custody-successor-schema'
            $offlineCustodySuccessor=$offlineCustodySuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
            Assert-MIR4ValidationRunnerDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $offlineCustodySuccessor) 'mir4-m42-02-validation-runner-offline-custody-successor-record'
            Assert-MIR4ValidationRunnerDecompositionV1 ((Get-FileHash -LiteralPath $compatibilityAuditSuccessorPath -Algorithm SHA256).Hash-ceq[string]$offlineCustodySuccessor.predecessor.receipt_sha256-and[string]$compatibilityAuditSuccessor.record_sha256-ceq[string]$offlineCustodySuccessor.predecessor.record_sha256) 'mir4-m42-02-validation-runner-offline-custody-successor-predecessor'
            foreach($binding in @($offlineCustodySuccessor.evolved_bindings)){
              $path=[string]$binding.path
              if($expectedBindingSha.ContainsKey($path)){
                Assert-MIR4ValidationRunnerDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-validation-runner-offline-custody-successor-binding' $path
                $expectedBindingSha[$path]=[string]$binding.current_sha256
              }
            }
            $releaseCapsuleSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Release-Capsule-DecompositionV1.json'
            if(Test-Path -LiteralPath $releaseCapsuleSuccessorPath -PathType Leaf){
              $releaseCapsuleSuccessorRaw=Get-Content -Raw -LiteralPath $releaseCapsuleSuccessorPath
              Assert-MIR4ValidationRunnerDecompositionV1 ($releaseCapsuleSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-release-capsule-decomposition-v1.schema.json')) 'mir4-m42-02-validation-runner-release-capsule-successor-schema'
              $releaseCapsuleSuccessor=$releaseCapsuleSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
              Assert-MIR4ValidationRunnerDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $releaseCapsuleSuccessor) 'mir4-m42-02-validation-runner-release-capsule-successor-record'
              Assert-MIR4ValidationRunnerDecompositionV1 ((Get-FileHash -LiteralPath $offlineCustodySuccessorPath -Algorithm SHA256).Hash-ceq[string]$releaseCapsuleSuccessor.predecessor.receipt_sha256-and[string]$offlineCustodySuccessor.record_sha256-ceq[string]$releaseCapsuleSuccessor.predecessor.record_sha256) 'mir4-m42-02-validation-runner-release-capsule-successor-predecessor'
              foreach($binding in @($releaseCapsuleSuccessor.evolved_bindings)){
                $path=[string]$binding.path
                if($expectedBindingSha.ContainsKey($path)){
                  Assert-MIR4ValidationRunnerDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-validation-runner-release-capsule-successor-binding' $path
                  $expectedBindingSha[$path]=[string]$binding.current_sha256
                }
              }
            }
          }
        }
      }
    }
  }
}
Assert-MIR4ValidationRunnerDecompositionV1 ([int]$inventory.command_count-gt0-and[int]$inventory.summary.unknown-eq0-and[int]$inventory.summary.duplicate_command_keys-eq0-and[string]$inventory.digest-cmatch'^sha256:[a-f0-9]{64}$') 'mir4-m42-02-validation-runner-inventory'
$controlExecutorSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Control-Executor-DecompositionV1.json'
if(Test-Path -LiteralPath $controlExecutorSuccessorPath -PathType Leaf){
  $controlExecutorSuccessorRaw=Get-Content -Raw -LiteralPath $controlExecutorSuccessorPath
  Assert-MIR4ValidationRunnerDecompositionV1 ($controlExecutorSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-control-executor-decomposition-v1.schema.json')) 'mir4-m42-02-validation-runner-control-executor-successor-schema'
  $controlExecutorSuccessor=$controlExecutorSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4ValidationRunnerDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $controlExecutorSuccessor) 'mir4-m42-02-validation-runner-control-executor-successor-record'
  $controlExecutorPredecessorPath=Join-Path $repo ([string]$controlExecutorSuccessor.predecessor.receipt)
  $controlExecutorPredecessor=Get-Content -Raw -LiteralPath $controlExecutorPredecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4ValidationRunnerDecompositionV1 ((Get-FileHash -LiteralPath $controlExecutorPredecessorPath -Algorithm SHA256).Hash-ceq[string]$controlExecutorSuccessor.predecessor.receipt_sha256-and[string]$controlExecutorPredecessor.record_sha256-ceq[string]$controlExecutorSuccessor.predecessor.record_sha256) 'mir4-m42-02-validation-runner-control-executor-successor-predecessor'
  foreach($binding in @($controlExecutorSuccessor.evolved_bindings)){
    $path=[string]$binding.path
    if($expectedBindingSha.ContainsKey($path)){
      Assert-MIR4ValidationRunnerDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-validation-runner-control-executor-successor-binding' $path
      $expectedBindingSha[$path]=[string]$binding.current_sha256
    }
  }
}
$supplyChainSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Supply-Chain-DecompositionV1.json'
if(Test-Path -LiteralPath $supplyChainSuccessorPath -PathType Leaf){
  $supplyChainSuccessorRaw=Get-Content -Raw -LiteralPath $supplyChainSuccessorPath
  Assert-MIR4ValidationRunnerDecompositionV1 ($supplyChainSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-supply-chain-decomposition-v1.schema.json')) 'mir4-m42-02-validation-runner-supply-chain-successor-schema'
  $supplyChainSuccessor=$supplyChainSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4ValidationRunnerDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $supplyChainSuccessor) 'mir4-m42-02-validation-runner-supply-chain-successor-record'
  Assert-MIR4ValidationRunnerDecompositionV1 ((Get-FileHash -LiteralPath $controlExecutorSuccessorPath -Algorithm SHA256).Hash-ceq[string]$supplyChainSuccessor.predecessor.receipt_sha256-and[string]$controlExecutorSuccessor.record_sha256-ceq[string]$supplyChainSuccessor.predecessor.record_sha256) 'mir4-m42-02-validation-runner-supply-chain-successor-predecessor'
  foreach($binding in @($supplyChainSuccessor.evolved_bindings)){
    $path=[string]$binding.path
    if($expectedBindingSha.ContainsKey($path)){
      Assert-MIR4ValidationRunnerDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-validation-runner-supply-chain-successor-binding' $path
      $expectedBindingSha[$path]=[string]$binding.current_sha256
    }
  }
}

Assert-MIR4ValidationRunnerDecompositionV1 (Update-MIR4M4202ExpectedBindingsThroughBridgeRetirement -RepoRoot $repo -ExpectedBindingSha $expectedBindingSha) 'mir4-m42-02-validation-runner-bridge-retirement-successor'
# This is deliberately a dirty-worktree guard only.  It proves that the
# current named files equal HEAD; it does not turn HEAD-derived hashes into a
# semantic or binding authority.  PS2 reconstruction above remains the
# independent historical proof, while current behavior is covered by the
# parse, bounded-surface, List, DocsOnly, and focused product checks.
Assert-MIR4ValidationRunnerDecompositionV1 (Test-MIR4M4202CommittedWorktreeFileConsistency -RepoRoot $repo -RelativePaths @($expectedBindingSha.Keys)) 'mir4-m42-02-validation-runner-current-binding-worktree-consistency'
Assert-MIR4ValidationRunnerDecompositionV1 (Test-MIR4M4202CommittedWorktreeFileConsistency -RepoRoot $repo -RelativePaths @($files|ForEach-Object{[string]$_.path})) 'mir4-m42-02-validation-runner-current-module-worktree-consistency'
Assert-MIR4ValidationRunnerDecompositionV1 ((Test-MIR4M4202PackageSourceSuccession -RepoRoot $repo -PredecessorSha256 ([string]$receipt.preservation.package_source_sha256) -CurrentSha256 $packageBefore)-and@($receipt.preservation.package_visible_delta).Count-eq0) 'mir4-m42-02-validation-runner-package-firewall'
Assert-MIR4ValidationRunnerDecompositionV1 (@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-m42-02-validation-runner-release-firewall'
Assert-MIR4ValidationRunnerDecompositionV1 ((Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-m42-02-validation-runner-package-mutation'

[pscustomobject][ordered]@{
  status='M42-02-PS2-VALIDATION-RUNNER-DECOMPOSITION-PASSED'
  facade_lines=[int]$receipt.decomposition.facade.current_lines
  application_lines=[int]$receipt.decomposition.application.lines
  modules=@($receipt.decomposition.modules).Count
  maximum_module_lines=(@($receipt.decomposition.modules|Measure-Object lines -Maximum).Maximum)
  f210_scenarios=[int]$receipt.semantic_contract.runtime_registry.profile_counts.f210
  package_source_sha256=$packageBefore
  package_visible=$false
  release_transition_authority=$false
}
