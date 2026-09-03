# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
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
Assert-MIR4ValidationRunnerDecompositionV1 (@($facadeErrors).Count-eq0-and$facadeAst.ParamBlock.Parameters.Count-eq18-and[int]$receipt.decomposition.facade.current_lines-le40) 'mir4-m42-02-validation-runner-facade'
Assert-MIR4ValidationRunnerDecompositionV1 ((Get-MIR4BootstrapTextSha256 -Path $facadePath)-ceq[string]$receipt.decomposition.facade.current_sha256) 'mir4-m42-02-validation-runner-facade-hash'

$files=@($receipt.decomposition.modules)+@($receipt.decomposition.application)
Assert-MIR4ValidationRunnerDecompositionV1 (@($receipt.decomposition.modules).Count-eq21-and@($files|Group-Object path|Where-Object{$_.Count-ne1}).Count-eq0) 'mir4-m42-02-validation-runner-module-count'
foreach($file in $files){
  $path=Join-Path $repo ([string]$file.path)
  $tokens=$null;$parseErrors=$null
  $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
  Assert-MIR4ValidationRunnerDecompositionV1 (@($parseErrors).Count-eq0-and(Get-MIR4BootstrapTextSha256 -Path $path)-ceq[string]$file.sha256) 'mir4-m42-02-validation-runner-module' ([string]$file.path)
}
Assert-MIR4ValidationRunnerDecompositionV1 (@($receipt.decomposition.modules|Where-Object{[int]$_.lines-gt600}).Count-eq0-and[int]$receipt.decomposition.application.lines-le400) 'mir4-m42-02-validation-runner-bounds'

Assert-MIR4ValidationRunnerDecompositionV1 ([bool]$receipt.public_contract.unchanged-and[string]$receipt.public_contract.previous_sha256-ceq[string]$receipt.public_contract.current_sha256) 'mir4-m42-02-validation-runner-public-contract'
Assert-MIR4ValidationRunnerDecompositionV1 ([bool]$receipt.semantic_contract.source_segments_exact-and[bool]$receipt.semantic_contract.scenario_names_and_groups_unchanged-and[bool]$receipt.semantic_contract.schema_2_result_contract_unchanged) 'mir4-m42-02-validation-runner-semantic-contract'
Assert-MIR4ValidationRunnerDecompositionV1 ([int]$receipt.semantic_contract.runtime_registry.profile_counts.f210-eq135-and[int]$receipt.semantic_contract.runtime_registry.profile_counts.f200-eq7-and[int]$receipt.semantic_contract.runtime_registry.profile_counts.f110-eq4-and[int]$receipt.semantic_contract.runtime_registry.profile_counts.f100-eq4) 'mir4-m42-02-validation-runner-target-counts'

$listOutput=(& pwsh -NoProfile -File $facadePath -List 2>&1|Out-String)
Assert-MIR4ValidationRunnerDecompositionV1 ($LASTEXITCODE-eq0-and$listOutput-match'package-zip-base'-and$listOutput-match'static-validation'-and$listOutput-notmatch'\[check\] info.json parses') 'mir4-m42-02-validation-runner-list-mode'
$docsOutput=(& pwsh -NoProfile -File $facadePath -DocsOnly 2>&1|Out-String)
Assert-MIR4ValidationRunnerDecompositionV1 ($LASTEXITCODE-eq0-and$docsOutput-match'MIR docs and governance lint passed'-and$docsOutput-notmatch'\[check\] info.json parses') 'mir4-m42-02-validation-runner-docs-mode'

$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
$expectedInventoryDigest=[string]$receipt.tooling_inventory.digest
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
  $expectedInventoryDigest=[string]$assuranceSuccessor.tooling_inventory.digest
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
    $expectedInventoryDigest=[string]$preFreezeSuccessor.tooling_inventory.digest
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
      $expectedInventoryDigest=[string]$bootstrapMaterializationSuccessor.tooling_inventory.digest
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
        $expectedInventoryDigest=[string]$assuranceReleaseSuccessor.tooling_inventory.digest
      }
    }
  }
}
Assert-MIR4ValidationRunnerDecompositionV1 ([int]$inventory.command_count-eq85-and[int]$inventory.summary.unknown-eq0-and[int]$inventory.summary.duplicate_command_keys-eq0-and[string]$inventory.digest-ceq$expectedInventoryDigest) 'mir4-m42-02-validation-runner-inventory'
foreach($binding in @($receipt.evolved_bindings)){
  $path=[string]$binding.path
  Assert-MIR4ValidationRunnerDecompositionV1 ((Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $path))-ceq[string]$expectedBindingSha[$path]-and-not[bool]$binding.package_visible-and-not[bool]$binding.release_authority) 'mir4-m42-02-validation-runner-evolved-binding' $path
}
Assert-MIR4ValidationRunnerDecompositionV1 ([string]$receipt.preservation.package_source_sha256-ceq$packageBefore-and@($receipt.preservation.package_visible_delta).Count-eq0) 'mir4-m42-02-validation-runner-package-firewall'
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
