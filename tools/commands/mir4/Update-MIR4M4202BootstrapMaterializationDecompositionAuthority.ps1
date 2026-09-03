[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,[switch]$Check)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function ConvertTo-MIR4M4202BootstrapMaterializationJson($Record){(($Record|ConvertTo-Json -Depth 100).Replace(([string][char]13+[char]10),[string][char]10)+[string][char]10)}
function Set-MIR4M4202BootstrapMaterializationProjection([string]$RelativePath,[string]$Text){
  $path=Join-Path $repo $RelativePath
  if($Check){
    $actual=if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::ReadAllText($path).Replace("`r`n","`n").Replace("`r","`n")}else{''}
    if($actual-cne$Text){throw "[mir4-m42-02-bootstrap-materialization-stale] $RelativePath"}
    return
  }
  $parent=Split-Path -Parent $path
  if(-not(Test-Path -LiteralPath $parent -PathType Container)){[void](New-Item -ItemType Directory -Path $parent)}
  [IO.File]::WriteAllText($path,$Text,[Text.UTF8Encoding]::new($false))
}
function Get-MIR4M4202BootstrapMaterializationAst([string]$RelativePath){
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $RelativePath),[ref]$tokens,[ref]$errors)
  if(@($errors).Count-ne0){throw "[mir4-m42-02-bootstrap-materialization-parse] $RelativePath"}
  $ast
}
function Get-MIR4M4202BootstrapMaterializationGitText([string]$Commit,[string]$RelativePath){
  $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName='git';$start.UseShellExecute=$false;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  [void]$start.ArgumentList.Add('-C');[void]$start.ArgumentList.Add($repo);[void]$start.ArgumentList.Add('show');[void]$start.ArgumentList.Add("${Commit}:$RelativePath")
  $process=[Diagnostics.Process]::Start($start);$text=$process.StandardOutput.ReadToEnd();$errorText=$process.StandardError.ReadToEnd();$process.WaitForExit()
  if($process.ExitCode-ne0){throw "[mir4-m42-02-bootstrap-materialization-git-source] $Commit|$RelativePath|$errorText"}
  $text.Replace("`r`n","`n").Replace("`r","`n")
}
function Get-MIR4M4202BootstrapMaterializationGitTextSha256([string]$Commit,[string]$RelativePath){Get-MIR4Sha256String -Value (Get-MIR4M4202BootstrapMaterializationGitText -Commit $Commit -RelativePath $RelativePath)}
function Get-MIR4M4202BootstrapMaterializationSlice([string[]]$Lines,[int]$Start,[int]$End){@($Lines[($Start-1)..($End-1)])}

$startingCommit='d21f1282d2c1f669b8ecca18bcb517a0f1cae18d';$startingTree='4d8646fd12034fbe5f38eadcd76150b77b0f19b5'
$predecessorPath='releases/migrations/MIR4-M42-02-Pre-Freeze-Release-DecompositionV1.json'
$predecessor=Get-Content -Raw -LiteralPath (Join-Path $repo $predecessorPath)|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$predecessor.status-cne'M42-02-PS4-PRE-FREEZE-RELEASE-DECOMPOSED'-or[string]$predecessor.next_fixed_point-cne'M42-02-PS5-BOOTSTRAP-MATERIALIZATION'){throw '[mir4-m42-02-bootstrap-materialization-predecessor]'}
$characterizationPath='releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
$characterization=Get-Content -Raw -LiteralPath (Join-Path $repo $characterizationPath)|ConvertFrom-Json -Depth 100 -DateKind String
$characterized=@($characterization.tracked_files|Where-Object{[string]$_.path-ceq'tools/lib/mir4/BootstrapMaterialization.ps1'})
if($characterized.Count-ne1-or[string]$characterized[0].sha256-cne'3B496E1D8DA0A772E4B1856761EBB3C40921742D0161D59811E360256901FB30'){throw '[mir4-m42-02-bootstrap-materialization-characterization]'}
$sourcePath='tools/lib/mir4/BootstrapMaterialization.ps1'
$sourceText=Get-MIR4M4202BootstrapMaterializationGitText -Commit $startingCommit -RelativePath $sourcePath
$sourceSha256=Get-MIR4Sha256String -Value $sourceText;$sourceLines=@($sourceText.Split([char]10))
if(-not$sourceText.EndsWith([string][char]10)-or$sourceSha256-cne'3B496E1D8DA0A772E4B1856761EBB3C40921742D0161D59811E360256901FB30'-or$sourceLines.Count-ne1873){throw '[mir4-m42-02-bootstrap-materialization-starting-source]'}
$moduleSpecs=@(
  [pscustomobject]@{name='DigestsAndRecords.ps1';role='cryptographic digests, canonical records, and historical hash reconciliation';start=5;end=203},
  [pscustomobject]@{name='SafePaths.ps1';role='contained paths, build-tree cleanup, and portable source enumeration';start=205;end=390},
  [pscustomobject]@{name='ArchiveComparison.ps1';role='deterministic archive construction, bounded reads, comparison, and safe expansion';start=392;end=889},
  [pscustomobject]@{name='GitSourceProof.ps1';role='Git tree transport, toolchain locks, and exact source proof';start=891;end=1229},
  [pscustomobject]@{name='CapsuleContract.ps1';role='capsule member roles, controller and authority closure, schemas, and controlled copies';start=1231;end=1421},
  [pscustomobject]@{name='CapsuleArtifacts.ps1';role='capsule artifact validation and deterministic source-capsule construction';start=1423;end=1872}
)
$moduleRoot='tools/lib/mir4/bootstrap-materialization';$expectedModules=@{}
foreach($spec in $moduleSpecs){
  $relative="$moduleRoot/$($spec.name)";$expected=((Get-MIR4M4202BootstrapMaterializationSlice -Lines $sourceLines -Start $spec.start -End $spec.end)-join[char]10)+[char]10
  $expectedModules[$relative]=$expected;Set-MIR4M4202BootstrapMaterializationProjection -RelativePath $relative -Text $expected
}
$expectedFacade=@'
if (-not (Get-Command Get-MIRPackageSourceRoots -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot "../validation/PackageIdentity.ps1")
}

. (Join-Path $PSScriptRoot 'bootstrap-materialization/DigestsAndRecords.ps1')
. (Join-Path $PSScriptRoot 'bootstrap-materialization/SafePaths.ps1')
. (Join-Path $PSScriptRoot 'bootstrap-materialization/ArchiveComparison.ps1')
. (Join-Path $PSScriptRoot 'bootstrap-materialization/GitSourceProof.ps1')
. (Join-Path $PSScriptRoot 'bootstrap-materialization/CapsuleContract.ps1')
. (Join-Path $PSScriptRoot 'bootstrap-materialization/CapsuleArtifacts.ps1')
'@.Replace("`r`n","`n")
Set-MIR4M4202BootstrapMaterializationProjection -RelativePath $sourcePath -Text $expectedFacade

$authorityValidationPath='tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1'
$authorityValidation=Get-MIR4M4202BootstrapMaterializationGitText -Commit $startingCommit -RelativePath $authorityValidationPath
$schemaMarker="    '.mir/releases/waves/mir4-r0/MIR4-Maintainer-Final-GitHub-Release-AuthorizationV1.json'"
$schemaBinding="    'releases/migrations/MIR4-M42-02-Bootstrap-Materialization-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-bootstrap-materialization-decomposition-v1.schema.json'`n"
$schemaIndex=$authorityValidation.IndexOf($schemaMarker,[StringComparison]::Ordinal)
if($schemaIndex-lt0){throw '[mir4-m42-02-bootstrap-materialization-schema-marker]'}
$authorityValidation=$authorityValidation.Insert($schemaIndex,$schemaBinding)
$successorMarker='  $staleAuthorityBindings = @()'
$successorIndex=$authorityValidation.IndexOf($successorMarker,[StringComparison]::Ordinal)
if($successorIndex-lt0){throw '[mir4-m42-02-bootstrap-materialization-successor-marker]'}
$successor=@'
  $bootstrapMaterializationReceiptPath = 'releases/migrations/MIR4-M42-02-Bootstrap-Materialization-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $bootstrapMaterializationReceiptPath) -PathType Leaf) {
    $bootstrapMaterialization = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $bootstrapMaterializationReceiptPath -Kind 'MIR4M4202BootstrapMaterializationDecompositionV1'
    if ([string]$bootstrapMaterialization.predecessor.receipt -cne $priorReceiptPath -or
        [string]$bootstrapMaterialization.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$bootstrapMaterialization.predecessor.record_sha256 -cne [string]$preFreezeRelease.record_sha256) {
      throw '[mir4-prefreeze-m42-02-bootstrap-materialization-predecessor]'
    }
    $bootstrapMaterializationEnrollmentBaselines = @{
      'tests/tooling/Test-MIR4PreFreezeReleaseDecompositionM4202.ps1'='B382CC2260F41B89207C690642DE41A405D51F00C9B5E439B3A8F41BADC996EB'
      'tools/lib/mir4/BootstrapMaterialization.ps1'='3B496E1D8DA0A772E4B1856761EBB3C40921742D0161D59811E360256901FB30'
      'tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1'='B3816A485BC68DB696598D2BAB637DE2EAD46DAE48ACA34DFAE6BAB904AA85C3'
    }
    $bootstrapMaterializationEvolvedPaths = @{}
    foreach ($binding in @($bootstrapMaterialization.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $bootstrapMaterializationEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$bootstrapMaterializationEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-bootstrap-materialization-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $bootstrapMaterializationEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-bootstrap-materialization-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $bootstrapMaterializationEvolvedPaths[$path] = $true
    }
    if ($bootstrapMaterializationEvolvedPaths.Count -ne 21 -or
        [string]$bootstrapMaterialization.status -cne 'M42-02-PS5-BOOTSTRAP-MATERIALIZATION-DECOMPOSED' -or
        [string]$bootstrapMaterialization.decomposition.responsibility -cne 'bootstrap-materialization' -or
        [string]$bootstrapMaterialization.next_fixed_point -cne 'M42-02-PS6-ASSURANCE-RELEASE' -or
        @($bootstrapMaterialization.decomposition.modules).Count -ne 6 -or
        -not [bool]$bootstrapMaterialization.public_contract.unchanged -or
        [int]$bootstrapMaterialization.public_contract.function_count -ne 51 -or
        -not [bool]$bootstrapMaterialization.semantic_contract.source_segments_exact -or
        [string]$bootstrapMaterialization.preservation.package_source_sha256 -cne (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)) {
      throw '[mir4-prefreeze-m42-02-bootstrap-materialization-scope]'
    }
    foreach ($property in $bootstrapMaterialization.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-bootstrap-materialization-transition] $($property.Name)" }
    }
    $priorReceiptPath = $bootstrapMaterializationReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
'@.Replace("`r`n","`n")
$authorityValidation=$authorityValidation.Insert($successorIndex,$successor+[char]10)
Set-MIR4M4202BootstrapMaterializationProjection -RelativePath $authorityValidationPath -Text $authorityValidation

$modules=@(foreach($spec in $moduleSpecs){
  $relative="$moduleRoot/$($spec.name)";$actual=[IO.File]::ReadAllText((Join-Path $repo $relative)).Replace("`r`n","`n").Replace("`r","`n")
  if($actual-cne[string]$expectedModules[$relative]){throw "[mir4-m42-02-bootstrap-materialization-segment] $relative"}
  $ast=Get-MIR4M4202BootstrapMaterializationAst $relative;$lineCount=@([IO.File]::ReadAllLines((Join-Path $repo $relative))).Count
  if($lineCount-gt600){throw "[mir4-m42-02-bootstrap-materialization-module-size] $relative|$lineCount"}
  [pscustomobject][ordered]@{path=$relative;role=[string]$spec.role;source_lines=[pscustomobject][ordered]@{start=[int]$spec.start;end=[int]$spec.end};sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $relative));hash_mode='canonical-text-v1';lines=$lineCount;function_count=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count;parse_errors=0}
})
if($modules.Count-ne6-or(@($modules|Measure-Object function_count -Sum).Sum)-ne51){throw '[mir4-m42-02-bootstrap-materialization-module-contract]'}
$facadeAst=Get-MIR4M4202BootstrapMaterializationAst $sourcePath;$facadeLines=@([IO.File]::ReadAllLines((Join-Path $repo $sourcePath))).Count
if(@($facadeAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count-ne0-or$facadeLines-gt20){throw '[mir4-m42-02-bootstrap-materialization-facade]'}
$oldTokens=$null;$oldErrors=$null;$oldAst=[Management.Automation.Language.Parser]::ParseInput($sourceText,[ref]$oldTokens,[ref]$oldErrors)
$oldFunctions=@($oldAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object{$_.Name})
$currentFunctions=@(foreach($spec in $moduleSpecs){(Get-MIR4M4202BootstrapMaterializationAst "$moduleRoot/$($spec.name)").FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object{$_.Name}})
$oldProjectionSha=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $oldFunctions);$currentProjectionSha=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $currentFunctions)
if($oldFunctions.Count-ne51-or($oldFunctions-join'|')-cne($currentFunctions-join'|')-or$oldProjectionSha-cne$currentProjectionSha){throw '[mir4-m42-02-bootstrap-materialization-public-contract]'}
$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
if([int]$inventory.command_count-ne85-or[int]$inventory.summary.unknown-ne0-or[int]$inventory.summary.duplicate_command_keys-ne0){throw '[mir4-m42-02-bootstrap-materialization-inventory]'}
$evolvedPaths=@(
  '.mir/assurance.json','.mir/control/paths.yml','.mir/modules.yml','.mir/test-impact.yml','assurance/catalog/tests.json','docs/architecture/module-boundaries.md','governance/automation/mir4-command-inventory-v1.json',
  'tests/architecture/Test-MIRArchitecture.ps1','tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1','tests/repository/Test-MIR4RepositoryFixedPoint.ps1','tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1',
  'tests/tooling/Test-MIR4PowerShellCommandRouterDecompositionM4202.ps1','tests/tooling/Test-MIR4ValidationRunnerDecompositionM4202.ps1','tests/tooling/Test-MIR4AssuranceEvidenceDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4PreFreezeReleaseDecompositionM4202.ps1','tests/tooling/Test-MIRAssurance.ps1','tests/tooling/Test-MIRVerificationSchemas.ps1','tools/lib/mir4/BootstrapMaterialization.ps1',
  'tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1','tools/mir/application/repository/RepositoryFixedPoint.ps1','validation/tests.yml'
)
$evolvedBindings=@($evolvedPaths|ForEach-Object{[pscustomobject][ordered]@{path=$_;previous_sha256=(Get-MIR4M4202BootstrapMaterializationGitTextSha256 -Commit $startingCommit -RelativePath $_);current_sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $_));hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}})
$packageSourceSha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receipt=[pscustomobject][ordered]@{
  schema=1;kind='MIR4M4202BootstrapMaterializationDecompositionV1';status='M42-02-PS5-BOOTSTRAP-MATERIALIZATION-DECOMPOSED';starting_dev=[pscustomobject][ordered]@{commit=$startingCommit;tree=$startingTree}
  predecessor=[pscustomobject][ordered]@{work_package='M42-02-PS4-PRE-FREEZE-RELEASE';receipt=$predecessorPath;receipt_sha256=(Get-FileHash -LiteralPath (Join-Path $repo $predecessorPath) -Algorithm SHA256).Hash.ToUpperInvariant();record_sha256=[string]$predecessor.record_sha256;status=[string]$predecessor.status}
  characterization=[pscustomobject][ordered]@{receipt=$characterizationPath;record_sha256=[string]$characterization.record_sha256;path=$sourcePath;sha256=[string]$characterized[0].sha256;lines=[int]$characterized[0].lines;responsibilities=@($characterized[0].responsibilities)}
  current_source=[pscustomobject][ordered]@{commit=$startingCommit;tree=$startingTree;path=$sourcePath;sha256=$sourceSha256;lines=1872;function_count=51;evolution_chain=@()}
  decomposition=[pscustomobject][ordered]@{responsibility='bootstrap-materialization';facade=[pscustomobject][ordered]@{path=$sourcePath;previous_sha256=$sourceSha256;current_sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $sourcePath));hash_mode='canonical-text-v1';previous_lines=1872;current_lines=$facadeLines;maximum_lines=20;function_count=0};module_root=$moduleRoot;module_count=$modules.Count;module_maximum_lines=600;modules=$modules;segment_algorithm='exact-current-function-source-slices-v1'}
  public_contract=[pscustomobject][ordered]@{projection_algorithm='ordered-powershell-function-name-list-v1';previous_sha256=$oldProjectionSha;current_sha256=$currentProjectionSha;unchanged=$true;function_count=$currentFunctions.Count}
  semantic_contract=[pscustomobject][ordered]@{source_segments_exact=$true;function_names_and_order_unchanged=$true;module_load_order_explicit=$true;digests_and_records_unchanged=$true;safe_paths_and_cleanup_unchanged=$true;archive_construction_and_comparison_unchanged=$true;git_source_proof_unchanged=$true;capsule_contract_unchanged=$true;capsule_artifacts_unchanged=$true;pre_freeze_authority_chain_extended_for_ps5=$true}
  tooling_inventory=[pscustomobject][ordered]@{path='governance/automation/mir4-command-inventory-v1.json';sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo 'governance/automation/mir4-command-inventory-v1.json'));hash_mode='canonical-text-v1';digest=[string]$inventory.digest;command_count=[int]$inventory.command_count;unknown=[int]$inventory.summary.unknown;duplicate_command_keys=[int]$inventory.summary.duplicate_command_keys}
  evolved_bindings=$evolvedBindings;preservation=[pscustomobject][ordered]@{package_source_sha256=$packageSourceSha256;package_visible_delta=@();gameplay=$false;saves=$true;settings=$true;migrations=$true;compatibility_claims=$true}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false};next_fixed_point='M42-02-PS6-ASSURANCE-RELEASE';record_sha256=''
}
$receipt.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $receipt;$json=ConvertTo-MIR4M4202BootstrapMaterializationJson $receipt
if(-not($json|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-bootstrap-materialization-decomposition-v1.schema.json'))){throw '[mir4-m42-02-bootstrap-materialization-receipt-schema]'}
Set-MIR4M4202BootstrapMaterializationProjection -RelativePath 'releases/migrations/MIR4-M42-02-Bootstrap-Materialization-DecompositionV1.json' -Text $json
$receipt
