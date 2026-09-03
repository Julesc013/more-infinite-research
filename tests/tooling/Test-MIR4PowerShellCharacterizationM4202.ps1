# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-MIR4M4202PowerShell([bool]$Condition,[string]$Code){if(-not$Condition){throw "[mir4-m42-02-powershell-test] $Code"}}

$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
$schemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-powershell-characterization-v1.schema.json'
$raw=Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4M4202PowerShell ($raw|Test-Json -SchemaFile $schemaPath) 'receipt-schema'
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202PowerShell (Test-MIR4BootstrapRecordHash -Record $receipt) 'receipt-record-hash'

$l6Path=Join-Path $repo ([string]$receipt.predecessor.receipt)
$l6Raw=Get-Content -Raw -LiteralPath $l6Path
$l6=$l6Raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202PowerShell ((Get-FileHash -LiteralPath $l6Path -Algorithm SHA256).Hash-ceq[string]$receipt.predecessor.receipt_sha256-and[string]$l6.record_sha256-ceq[string]$receipt.predecessor.record_sha256) 'predecessor'

$expectedTrackedSha=@{};$expectedTrackedFunctions=@{};$expectedAuthoritySha=@{}
foreach($row in @($receipt.tracked_files)){$expectedTrackedSha[[string]$row.path]=[string]$row.sha256;$expectedTrackedFunctions[[string]$row.path]=[int]$row.function_count}
foreach($binding in @($receipt.authority_bindings)){$expectedAuthoritySha[[string]$binding.path]=[string]$binding.sha256}
$successorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-PowerShell-Command-Router-DecompositionV1.json'
$hasSuccessor=Test-Path -LiteralPath $successorPath -PathType Leaf
$expectedInventorySha=[string]$receipt.inventory.sha256
$expectedInventoryDigest=[string]$receipt.inventory.digest
$hasValidationSuccessor=$false
$hasAssuranceSuccessor=$false
$hasPreFreezeReleaseSuccessor=$false
$preFreezeReleaseThresholdPaths=@()
if($hasSuccessor){
  $successorRaw=Get-Content -Raw -LiteralPath $successorPath
  Assert-MIR4M4202PowerShell ($successorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-powershell-command-router-decomposition-v1.schema.json')) 'successor-schema'
  $successor=$successorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202PowerShell (Test-MIR4BootstrapRecordHash -Record $successor) 'successor-record-hash'
  Assert-MIR4M4202PowerShell ((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash-ceq[string]$successor.predecessor.receipt_sha256-and[string]$receipt.record_sha256-ceq[string]$successor.predecessor.record_sha256) 'successor-predecessor'
  Assert-MIR4M4202PowerShell ([string]$successor.decomposition.facade.previous_sha256-ceq[string]$expectedTrackedSha['tools/mir/cli/Invoke-MIRCommandRouter.ps1']) 'successor-router-predecessor'
  $expectedTrackedSha['tools/mir/cli/Invoke-MIRCommandRouter.ps1']=[string]$successor.decomposition.facade.current_sha256
  $expectedTrackedFunctions['tools/mir/cli/Invoke-MIRCommandRouter.ps1']=[int]$successor.decomposition.facade_function_count
  foreach($binding in @($successor.evolved_bindings)){
    $path=[string]$binding.path
    if($expectedTrackedSha.ContainsKey($path)-and$path-cne'tools/mir/cli/Invoke-MIRCommandRouter.ps1'){
      Assert-MIR4M4202PowerShell ([string]$binding.previous_sha256-ceq[string]$expectedTrackedSha[$path]) "successor-tracked-predecessor-$path"
      $expectedTrackedSha[$path]=[string]$binding.current_sha256
    }
    if($expectedAuthoritySha.ContainsKey($path)){
      Assert-MIR4M4202PowerShell ([string]$binding.previous_sha256-ceq[string]$expectedAuthoritySha[$path]) "successor-authority-predecessor-$path"
      $expectedAuthoritySha[$path]=[string]$binding.current_sha256
    }
  }
  $inventoryBinding=@($successor.evolved_bindings|Where-Object{[string]$_.path-ceq[string]$receipt.inventory.path})
  Assert-MIR4M4202PowerShell ($inventoryBinding.Count-eq1-and[string]$inventoryBinding[0].previous_sha256-ceq[string]$receipt.inventory.sha256) 'successor-inventory-predecessor'
  $expectedInventorySha=[string]$successor.public_contract.inventory.sha256
  $expectedInventoryDigest=[string]$successor.public_contract.inventory.digest

  $validationSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Validation-Runner-DecompositionV1.json'
  $hasValidationSuccessor=Test-Path -LiteralPath $validationSuccessorPath -PathType Leaf
  if($hasValidationSuccessor){
    $validationSuccessorRaw=Get-Content -Raw -LiteralPath $validationSuccessorPath
    Assert-MIR4M4202PowerShell ($validationSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-validation-runner-decomposition-v1.schema.json')) 'validation-successor-schema'
    $validationSuccessor=$validationSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR4M4202PowerShell (Test-MIR4BootstrapRecordHash -Record $validationSuccessor) 'validation-successor-record-hash'
    Assert-MIR4M4202PowerShell ((Get-FileHash -LiteralPath $successorPath -Algorithm SHA256).Hash-ceq[string]$validationSuccessor.predecessor.receipt_sha256-and[string]$successor.record_sha256-ceq[string]$validationSuccessor.predecessor.record_sha256) 'validation-successor-predecessor'
    Assert-MIR4M4202PowerShell ([string]$validationSuccessor.decomposition.facade.previous_sha256-ceq[string]$expectedTrackedSha['scripts/Invoke-MIRValidation.ps1']) 'validation-successor-source-predecessor'
    $expectedTrackedSha['scripts/Invoke-MIRValidation.ps1']=[string]$validationSuccessor.decomposition.facade.current_sha256
    $expectedTrackedFunctions['scripts/Invoke-MIRValidation.ps1']=0
    foreach($binding in @($validationSuccessor.evolved_bindings)){
      $path=[string]$binding.path
      if($expectedTrackedSha.ContainsKey($path)-and$path-cne'scripts/Invoke-MIRValidation.ps1'){
        Assert-MIR4M4202PowerShell ([string]$binding.previous_sha256-ceq[string]$expectedTrackedSha[$path]) "validation-successor-tracked-predecessor-$path"
        $expectedTrackedSha[$path]=[string]$binding.current_sha256
      }
      if($expectedAuthoritySha.ContainsKey($path)){
        Assert-MIR4M4202PowerShell ([string]$binding.previous_sha256-ceq[string]$expectedAuthoritySha[$path]) "validation-successor-authority-predecessor-$path"
        $expectedAuthoritySha[$path]=[string]$binding.current_sha256
      }
    }
    $expectedInventorySha=[string]$validationSuccessor.tooling_inventory.sha256
    $expectedInventoryDigest=[string]$validationSuccessor.tooling_inventory.digest

    $assuranceSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Assurance-Evidence-DecompositionV1.json'
    $hasAssuranceSuccessor=Test-Path -LiteralPath $assuranceSuccessorPath -PathType Leaf
    if($hasAssuranceSuccessor){
      $assuranceSuccessorRaw=Get-Content -Raw -LiteralPath $assuranceSuccessorPath
      Assert-MIR4M4202PowerShell ($assuranceSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-assurance-evidence-decomposition-v1.schema.json')) 'assurance-successor-schema'
      $assuranceSuccessor=$assuranceSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
      Assert-MIR4M4202PowerShell (Test-MIR4BootstrapRecordHash -Record $assuranceSuccessor) 'assurance-successor-record-hash'
      Assert-MIR4M4202PowerShell ((Get-FileHash -LiteralPath $validationSuccessorPath -Algorithm SHA256).Hash-ceq[string]$assuranceSuccessor.predecessor.receipt_sha256-and[string]$validationSuccessor.record_sha256-ceq[string]$assuranceSuccessor.predecessor.record_sha256) 'assurance-successor-predecessor'
      Assert-MIR4M4202PowerShell ([string]$assuranceSuccessor.decomposition.facade.previous_sha256-ceq[string]$expectedTrackedSha['tools/lib/assurance/Evidence.ps1']) 'assurance-successor-source-predecessor'
      $expectedTrackedSha['tools/lib/assurance/Evidence.ps1']=[string]$assuranceSuccessor.decomposition.facade.current_sha256
      $expectedTrackedFunctions['tools/lib/assurance/Evidence.ps1']=0
      foreach($binding in @($assuranceSuccessor.evolved_bindings)){
        $path=[string]$binding.path
        if($expectedTrackedSha.ContainsKey($path)-and$path-cne'tools/lib/assurance/Evidence.ps1'){
          Assert-MIR4M4202PowerShell ([string]$binding.previous_sha256-ceq[string]$expectedTrackedSha[$path]) "assurance-successor-tracked-predecessor-$path"
          $expectedTrackedSha[$path]=[string]$binding.current_sha256
        }
        if($expectedAuthoritySha.ContainsKey($path)){
          Assert-MIR4M4202PowerShell ([string]$binding.previous_sha256-ceq[string]$expectedAuthoritySha[$path]) "assurance-successor-authority-predecessor-$path"
          $expectedAuthoritySha[$path]=[string]$binding.current_sha256
        }
      }
      $expectedInventorySha=[string]$assuranceSuccessor.tooling_inventory.sha256
      $expectedInventoryDigest=[string]$assuranceSuccessor.tooling_inventory.digest
      $preFreezeReleaseSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Pre-Freeze-Release-DecompositionV1.json'
      $hasPreFreezeReleaseSuccessor=Test-Path -LiteralPath $preFreezeReleaseSuccessorPath -PathType Leaf
      if($hasPreFreezeReleaseSuccessor){
        $preFreezeReleaseSuccessorRaw=Get-Content -Raw -LiteralPath $preFreezeReleaseSuccessorPath
        Assert-MIR4M4202PowerShell ($preFreezeReleaseSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-pre-freeze-release-decomposition-v1.schema.json')) 'pre-freeze-release-successor-schema'
        $preFreezeReleaseSuccessor=$preFreezeReleaseSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
        Assert-MIR4M4202PowerShell (Test-MIR4BootstrapRecordHash -Record $preFreezeReleaseSuccessor) 'pre-freeze-release-successor-record-hash'
        $preFreezeReleaseThresholdPaths=@($preFreezeReleaseSuccessor.decomposition.modules|Where-Object{[int]$_.lines-ge600}|ForEach-Object{[string]$_.path})
        Assert-MIR4M4202PowerShell ((Get-FileHash -LiteralPath $assuranceSuccessorPath -Algorithm SHA256).Hash-ceq[string]$preFreezeReleaseSuccessor.predecessor.receipt_sha256-and[string]$assuranceSuccessor.record_sha256-ceq[string]$preFreezeReleaseSuccessor.predecessor.record_sha256) 'pre-freeze-release-successor-predecessor'
        Assert-MIR4M4202PowerShell ([string]$preFreezeReleaseSuccessor.current_source.sha256-ceq[string]$expectedTrackedSha['tools/lib/mir4/PreFreezeRelease.ps1']) 'pre-freeze-release-successor-source-predecessor'
        $expectedTrackedSha['tools/lib/mir4/PreFreezeRelease.ps1']=[string]$preFreezeReleaseSuccessor.decomposition.facade.current_sha256
        $expectedTrackedFunctions['tools/lib/mir4/PreFreezeRelease.ps1']=0
        foreach($binding in @($preFreezeReleaseSuccessor.evolved_bindings)){
          $path=[string]$binding.path
          if($expectedTrackedSha.ContainsKey($path)-and$path-cne'tools/lib/mir4/PreFreezeRelease.ps1'){
            Assert-MIR4M4202PowerShell ([string]$binding.previous_sha256-ceq[string]$expectedTrackedSha[$path]) "pre-freeze-release-successor-tracked-predecessor-$path"
            $expectedTrackedSha[$path]=[string]$binding.current_sha256
          }
          if($expectedAuthoritySha.ContainsKey($path)){
            Assert-MIR4M4202PowerShell ([string]$binding.previous_sha256-ceq[string]$expectedAuthoritySha[$path]) "pre-freeze-release-successor-authority-predecessor-$path"
            $expectedAuthoritySha[$path]=[string]$binding.current_sha256
          }
        }
        $expectedInventorySha=[string]$preFreezeReleaseSuccessor.tooling_inventory.sha256
        $expectedInventoryDigest=[string]$preFreezeReleaseSuccessor.tooling_inventory.digest
      }
    }
  }
}
$inventoryPath=Join-Path $repo ([string]$receipt.inventory.path)
$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
Assert-MIR4M4202PowerShell ([string]$receipt.inventory.hash_mode-ceq'canonical-text-v1'-and(Get-MIR4BootstrapTextSha256 -Path $inventoryPath)-ceq$expectedInventorySha-and[string]$inventory.digest-ceq$expectedInventoryDigest-and[int]$inventory.summary.unknown-eq0) 'inventory'
$threshold=@($inventory.implementation_files|Where-Object{[string]$_.classification-ceq'canonical-internal'-and[int]$_.lines-ge600}|Sort-Object path)
$expectedThreshold=@(
  @($receipt.tracked_files|Where-Object{-not($hasSuccessor-and[string]$_.path-ceq'tools/mir/cli/Invoke-MIRCommandRouter.ps1')-and-not($hasValidationSuccessor-and[string]$_.path-ceq'scripts/Invoke-MIRValidation.ps1')-and-not($hasAssuranceSuccessor-and[string]$_.path-ceq'tools/lib/assurance/Evidence.ps1')-and-not($hasPreFreezeReleaseSuccessor-and[string]$_.path-ceq'tools/lib/mir4/PreFreezeRelease.ps1')}|ForEach-Object{[string]$_.path})
  @($preFreezeReleaseThresholdPaths)
)|Sort-Object
Assert-MIR4M4202PowerShell ($threshold.Count-eq$expectedThreshold.Count-and@($receipt.tracked_files).Count-eq20) 'threshold-count'
Assert-MIR4M4202PowerShell ((@($threshold|ForEach-Object{[string]$_.path})-join'|')-ceq($expectedThreshold-join'|')) 'threshold-paths'
foreach($row in @($receipt.tracked_files)){
  $path=Join-Path $repo ([string]$row.path)
  $tokens=$null;$parseErrors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
  Assert-MIR4M4202PowerShell (@($parseErrors).Count-eq0) "parse-$($row.path)"
  Assert-MIR4M4202PowerShell ([string]$row.hash_mode-ceq'canonical-text-v1'-and(Get-MIR4BootstrapTextSha256 -Path $path)-ceq[string]$expectedTrackedSha[[string]$row.path]) "hash-$($row.path)"
  Assert-MIR4M4202PowerShell (@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count-eq[int]$expectedTrackedFunctions[[string]$row.path]) "functions-$($row.path)"
}
Assert-MIR4M4202PowerShell (@($receipt.tracked_files|Where-Object{[string]$_.decision-ceq'decompose'}).Count-eq11-and@($receipt.decomposition_sequence).Count-eq11) 'decomposition-count'
Assert-MIR4M4202PowerShell (@($receipt.tracked_files|Where-Object{[string]$_.decision-ceq'retain-with-explicit-waiver'}).Count-eq9-and@($receipt.waivers).Count-eq9) 'waiver-count'
Assert-MIR4M4202PowerShell (@($receipt.authority_bindings).Count-eq12-and@($receipt.authority_bindings|Group-Object path|Where-Object{$_.Count-ne1}).Count-eq0) 'authority-binding-count'
foreach($binding in @($receipt.authority_bindings)){
  Assert-MIR4M4202PowerShell ([string]$binding.hash_mode-ceq'canonical-text-v1'-and-not[bool]$binding.package_visible) "authority-mode-$($binding.path)"
  $bindingPath=[string]$binding.path
  $actualAuthoritySha=Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $bindingPath)
  $expectedAuthorityBindingSha=[string]$expectedAuthoritySha[$bindingPath]
  Assert-MIR4M4202PowerShell ($actualAuthoritySha-ceq$expectedAuthorityBindingSha) "authority-hash-$bindingPath"
}
Assert-MIR4M4202PowerShell ([string]$receipt.decomposition_sequence[0].node-ceq'M42-02-PS1-COMMAND-ROUTER'-and[string]$receipt.next_fixed_point-ceq'M42-02-PS1-COMMAND-ROUTER') 'next-node'
Assert-MIR4M4202PowerShell ([int]$receipt.architecture_reconciliation.canonical_output_count-eq267-and[int]$receipt.architecture_reconciliation.assigned_output_count-eq267) 'architecture-reconciliation'
Assert-MIR4M4202PowerShell ([string]$receipt.preservation.package_source_sha256-ceq(Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)-and@($receipt.preservation.package_visible_delta).Count-eq0) 'package-preservation'
Assert-MIR4M4202PowerShell (@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'release-firewall'

[pscustomobject][ordered]@{status='passed';test_id='static.mir4-powershell-characterization-m42-02';reviewed_files=20;decompose=11;waivers=9;next_fixed_point=[string]$receipt.next_fixed_point;package_source_sha256=[string]$receipt.preservation.package_source_sha256;record_sha256=[string]$receipt.record_sha256;publication=$false}|ConvertTo-Json -Depth 10
