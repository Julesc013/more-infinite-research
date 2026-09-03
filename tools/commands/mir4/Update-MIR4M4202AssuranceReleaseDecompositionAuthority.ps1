[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,[switch]$Check)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function ConvertTo-MIR4M4202AssuranceReleaseJson($Record){(($Record|ConvertTo-Json -Depth 100).Replace(([string][char]13+[char]10),[string][char]10)+[string][char]10)}
function Set-MIR4M4202AssuranceReleaseProjection([string]$RelativePath,[string]$Text){
  $path=Join-Path $repo $RelativePath
  if($Check){
    $actual=if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::ReadAllText($path).Replace("`r`n","`n").Replace("`r","`n")}else{''}
    if($actual-cne$Text){throw "[mir4-m42-02-assurance-release-stale] $RelativePath"}
    return
  }
  $parent=Split-Path -Parent $path
  if(-not(Test-Path -LiteralPath $parent -PathType Container)){[void](New-Item -ItemType Directory -Path $parent)}
  [IO.File]::WriteAllText($path,$Text,[Text.UTF8Encoding]::new($false))
}
function Get-MIR4M4202AssuranceReleaseAst([string]$RelativePath){
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $RelativePath),[ref]$tokens,[ref]$errors)
  if(@($errors).Count-ne0){throw "[mir4-m42-02-assurance-release-parse] $RelativePath"}
  $ast
}
function Get-MIR4M4202AssuranceReleaseGitText([string]$Commit,[string]$RelativePath){
  $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName='git';$start.UseShellExecute=$false;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  [void]$start.ArgumentList.Add('-C');[void]$start.ArgumentList.Add($repo);[void]$start.ArgumentList.Add('show');[void]$start.ArgumentList.Add("${Commit}:$RelativePath")
  $process=[Diagnostics.Process]::Start($start);$text=$process.StandardOutput.ReadToEnd();$errorText=$process.StandardError.ReadToEnd();$process.WaitForExit()
  if($process.ExitCode-ne0){throw "[mir4-m42-02-assurance-release-git-source] $Commit|$RelativePath|$errorText"}
  $text.Replace("`r`n","`n").Replace("`r","`n")
}
function Get-MIR4M4202AssuranceReleaseGitTextSha256([string]$Commit,[string]$RelativePath){Get-MIR4Sha256String -Value (Get-MIR4M4202AssuranceReleaseGitText -Commit $Commit -RelativePath $RelativePath)}
function Get-MIR4M4202AssuranceReleaseSlice([string[]]$Lines,[int]$Start,[int]$End){@($Lines[($Start-1)..($End-1)])}

$startingCommit='221783fa112a76eefd74ccdf1c980f5e0ff18f5c';$startingTree='9fa0a053717a857350eac5e4b9de593ca054308e'
$predecessorPath='releases/migrations/MIR4-M42-02-Bootstrap-Materialization-DecompositionV1.json'
$predecessor=Get-Content -Raw -LiteralPath (Join-Path $repo $predecessorPath)|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$predecessor.status-cne'M42-02-PS5-BOOTSTRAP-MATERIALIZATION-DECOMPOSED'-or[string]$predecessor.next_fixed_point-cne'M42-02-PS6-ASSURANCE-RELEASE'){throw '[mir4-m42-02-assurance-release-predecessor]'}
$characterizationPath='releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
$characterization=Get-Content -Raw -LiteralPath (Join-Path $repo $characterizationPath)|ConvertFrom-Json -Depth 100 -DateKind String
$sourcePath='tools/lib/assurance/Release.ps1';$sourceSha256='B9B0F07F385A59C000E3F5D627481A28DA6BE9522F34B08BAADCF1B1B48E9AB9'
$characterized=@($characterization.tracked_files|Where-Object{[string]$_.path-ceq$sourcePath})
if($characterized.Count-ne1-or[string]$characterized[0].sha256-cne$sourceSha256){throw '[mir4-m42-02-assurance-release-characterization]'}
$sourceText=Get-MIR4M4202AssuranceReleaseGitText -Commit $startingCommit -RelativePath $sourcePath
$sourceLines=@($sourceText.Split([char]10))
if(-not$sourceText.EndsWith([string][char]10)-or(Get-MIR4Sha256String -Value $sourceText)-cne$sourceSha256-or$sourceLines.Count-ne1811){throw '[mir4-m42-02-assurance-release-starting-source]'}
$moduleSpecs=@(
  [pscustomobject]@{name='CandidatePlanning.ps1';role='candidate archive identity, local playtest planning, release planning, and candidate authority';start=5;end=344},
  [pscustomobject]@{name='SealAuthority.ps1';role='seal source authority and performance evidence identity';start=346;end=423},
  [pscustomobject]@{name='SealCreation.ps1';role='release seal construction and evidence closure';start=425;end=580},
  [pscustomobject]@{name='SealVerification.ps1';role='release seal verification and exact authority rejection';start=582;end=799}
)
$moduleRoot='tools/lib/assurance/release';$expectedModules=@{}
foreach($spec in $moduleSpecs){
  $relative="$moduleRoot/$($spec.name)";$expected=((Get-MIR4M4202AssuranceReleaseSlice -Lines $sourceLines -Start $spec.start -End $spec.end)-join[char]10)+[char]10
  $expectedModules[$relative]=$expected;Set-MIR4M4202AssuranceReleaseProjection -RelativePath $relative -Text $expected
}
$selfTestPath='tests/tooling/support/MIRAssuranceSelfTest.ps1'
$expectedSelfTest=((Get-MIR4M4202AssuranceReleaseSlice -Lines $sourceLines -Start 801 -End 1810)-join[char]10)+[char]10
Set-MIR4M4202AssuranceReleaseProjection -RelativePath $selfTestPath -Text $expectedSelfTest
$expectedFacade=@'
. (Join-Path $PSScriptRoot "Hashing.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "validation\ReleaseAttestations.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "mir4\BootstrapMaterialization.ps1")

. (Join-Path $PSScriptRoot 'release/CandidatePlanning.ps1')
. (Join-Path $PSScriptRoot 'release/SealAuthority.ps1')
. (Join-Path $PSScriptRoot 'release/SealCreation.ps1')
. (Join-Path $PSScriptRoot 'release/SealVerification.ps1')
'@.Replace("`r`n","`n")
Set-MIR4M4202AssuranceReleaseProjection -RelativePath $sourcePath -Text $expectedFacade

$entrypointPath='scripts/Invoke-MIRAssurance.ps1';$entrypoint=Get-MIR4M4202AssuranceReleaseGitText -Commit $startingCommit -RelativePath $entrypointPath
$commandMarker='$command = if ($Args.Count -gt 0) { [string]$Args[0] } else { "help" }'+[char]10
if(($entrypoint.Split($commandMarker).Count-1)-ne1){throw '[mir4-m42-02-assurance-release-entrypoint-marker]'}
$selfTestLoad=@'
if ($command -ceq "self-test") {
  . (Join-Path $repo "tests/tooling/support/MIRAssuranceSelfTest.ps1")
}
'@.Replace("`r`n","`n")
$entrypoint=$entrypoint.Replace($commandMarker,$commandMarker+$selfTestLoad+[char]10)
Set-MIR4M4202AssuranceReleaseProjection -RelativePath $entrypointPath -Text $entrypoint

$assuranceTestPath='tests/tooling/Test-MIRAssurance.ps1';$assuranceTest=Get-MIR4M4202AssuranceReleaseGitText -Commit $startingCommit -RelativePath $assuranceTestPath
$releaseSourceMarker='$releaseAssuranceSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\Release.ps1")'+[char]10
if(($assuranceTest.Split($releaseSourceMarker).Count-1)-ne1){throw '[mir4-m42-02-assurance-release-test-source-marker]'}
$releaseSources=@'
$releaseAssuranceFacadeSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\Release.ps1")
$releaseAssuranceSource = @(
  $releaseAssuranceFacadeSource
  Get-ChildItem -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\release") -File -Filter "*.ps1" |
    Sort-Object Name |
    ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }
) -join "`n"
'@.Replace("`r`n","`n")
$testSources=@'
$assuranceSelfTestSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tests\tooling\support\MIRAssuranceSelfTest.ps1")
$assuranceEntryPointSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\Invoke-MIRAssurance.ps1")
'@.Replace("`r`n","`n")
$assuranceTest=$assuranceTest.Replace($releaseSourceMarker,$releaseSources+[char]10+$testSources+[char]10)
$oldTrustCheck='if (-not $releaseAssuranceSource.Contains($requiredTrustSelfTestSnippet)) {'
if(($assuranceTest.Split($oldTrustCheck).Count-1)-ne1){throw '[mir4-m42-02-assurance-release-test-trust-marker]'}
$assuranceTest=$assuranceTest.Replace($oldTrustCheck,'if (-not $assuranceSelfTestSource.Contains($requiredTrustSelfTestSnippet)) {')
$catalogMarker='$ids = @($catalog.tests | ForEach-Object { [string]$_.id })'
$boundaryCheck=@'
if ($releaseAssuranceFacadeSource.Contains('function Invoke-MIRAssuranceSelfTest')) { throw 'Release authority still embeds assurance self-test implementation.' }
if (-not $assuranceEntryPointSource.Contains('tests/tooling/support/MIRAssuranceSelfTest.ps1')) { throw 'Assurance self-test command does not load canonical test support.' }

'@.Replace("`r`n","`n")
if(($assuranceTest.Split($catalogMarker).Count-1)-ne1){throw '[mir4-m42-02-assurance-release-test-boundary-marker]'}
$assuranceTest=$assuranceTest.Replace($catalogMarker,$boundaryCheck+$catalogMarker)
$releaseLibraryMarker='$assuranceReleaseLibrary = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\Release.ps1")'+[char]10
if(($assuranceTest.Split($releaseLibraryMarker).Count-1)-ne1){throw '[mir4-m42-02-assurance-release-test-library-marker]'}
$assuranceTest=$assuranceTest.Replace($releaseLibraryMarker,'$assuranceReleaseLibrary = $releaseAssuranceSource'+[char]10)
$sealSourceMarker='$releaseAssurance = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\Release.ps1")'+[char]10
if(($assuranceTest.Split($sealSourceMarker).Count-1)-ne1){throw '[mir4-m42-02-assurance-release-test-seal-source-marker]'}
$assuranceTest=$assuranceTest.Replace($sealSourceMarker,'$releaseAssurance = $releaseAssuranceSource'+[char]10)
Set-MIR4M4202AssuranceReleaseProjection -RelativePath $assuranceTestPath -Text $assuranceTest

$authorityValidationPath='tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1'
$authorityValidation=Get-MIR4M4202AssuranceReleaseGitText -Commit $startingCommit -RelativePath $authorityValidationPath
$schemaMarker="    '.mir/releases/waves/mir4-r0/MIR4-Maintainer-Final-GitHub-Release-AuthorizationV1.json'"
$schemaBinding="    'releases/migrations/MIR4-M42-02-Assurance-Release-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-assurance-release-decomposition-v1.schema.json'`n"
$schemaIndex=$authorityValidation.IndexOf($schemaMarker,[StringComparison]::Ordinal)
if($schemaIndex-lt0){throw '[mir4-m42-02-assurance-release-schema-marker]'}
$authorityValidation=$authorityValidation.Insert($schemaIndex,$schemaBinding)
$successorMarker='  $staleAuthorityBindings = @()';$successorIndex=$authorityValidation.IndexOf($successorMarker,[StringComparison]::Ordinal)
if($successorIndex-lt0){throw '[mir4-m42-02-assurance-release-successor-marker]'}
$successor=@'
  $assuranceReleaseReceiptPath = 'releases/migrations/MIR4-M42-02-Assurance-Release-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $assuranceReleaseReceiptPath) -PathType Leaf) {
    $assuranceRelease = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $assuranceReleaseReceiptPath -Kind 'MIR4M4202AssuranceReleaseDecompositionV1'
    if ([string]$assuranceRelease.predecessor.receipt -cne $priorReceiptPath -or
        [string]$assuranceRelease.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$assuranceRelease.predecessor.record_sha256 -cne [string]$bootstrapMaterialization.record_sha256) {
      throw '[mir4-prefreeze-m42-02-assurance-release-predecessor]'
    }
    $assuranceReleaseEnrollmentBaselines = @{
      'scripts/Invoke-MIRAssurance.ps1'='FAB4B763803218D33E584958BA92403FB3631B6BB3B1A893BEC5DC3F59D52600'
      'tests/tooling/Test-MIR4BootstrapMaterializationDecompositionM4202.ps1'='DE64AAA6E87D27C00B0AE01A71B2297805E10753F6101DE5AF8499A3A22807F7'
      'tools/lib/assurance/Release.ps1'='B9B0F07F385A59C000E3F5D627481A28DA6BE9522F34B08BAADCF1B1B48E9AB9'
    }
    $assuranceReleaseEvolvedPaths = @{}
    foreach ($binding in @($assuranceRelease.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $assuranceReleaseEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$assuranceReleaseEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-assurance-release-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $assuranceReleaseEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-assurance-release-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $assuranceReleaseEvolvedPaths[$path] = $true
    }
    if ($assuranceReleaseEvolvedPaths.Count -ne 23 -or
        [string]$assuranceRelease.status -cne 'M42-02-PS6-ASSURANCE-RELEASE-DECOMPOSED' -or
        [string]$assuranceRelease.decomposition.responsibility -cne 'assurance-release' -or
        [string]$assuranceRelease.next_fixed_point -cne 'M42-02-PS7-COMPATIBILITY-AUDIT' -or
        @($assuranceRelease.decomposition.modules).Count -ne 4 -or
        [string]$assuranceRelease.decomposition.self_test.authority -cne 'canonical-executable-test-support' -or
        -not [bool]$assuranceRelease.public_contract.unchanged -or
        -not [bool]$assuranceRelease.semantic_contract.embedded_self_test_removed_from_release_authority -or
        [string]$assuranceRelease.preservation.package_source_sha256 -cne (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)) {
      throw '[mir4-prefreeze-m42-02-assurance-release-scope]'
    }
    foreach ($property in $assuranceRelease.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-assurance-release-transition] $($property.Name)" }
    }
    $priorReceiptPath = $assuranceReleaseReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
'@.Replace("`r`n","`n")
$authorityValidation=$authorityValidation.Insert($successorIndex,$successor+[char]10)
Set-MIR4M4202AssuranceReleaseProjection -RelativePath $authorityValidationPath -Text $authorityValidation

$modules=@(foreach($spec in $moduleSpecs){
  $relative="$moduleRoot/$($spec.name)";$actual=[IO.File]::ReadAllText((Join-Path $repo $relative)).Replace("`r`n","`n").Replace("`r","`n")
  if($actual-cne[string]$expectedModules[$relative]){throw "[mir4-m42-02-assurance-release-segment] $relative"}
  $ast=Get-MIR4M4202AssuranceReleaseAst $relative;$lineCount=@([IO.File]::ReadAllLines((Join-Path $repo $relative))).Count
  if($lineCount-gt400){throw "[mir4-m42-02-assurance-release-module-size] $relative|$lineCount"}
  [pscustomobject][ordered]@{path=$relative;role=[string]$spec.role;source_lines=[pscustomobject][ordered]@{start=[int]$spec.start;end=[int]$spec.end};sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $relative));hash_mode='canonical-text-v1';lines=$lineCount;function_count=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count;parse_errors=0}
})
$selfTestAst=Get-MIR4M4202AssuranceReleaseAst $selfTestPath;$selfTestLines=@([IO.File]::ReadAllLines((Join-Path $repo $selfTestPath))).Count
if($modules.Count-ne4-or(@($modules|Measure-Object function_count -Sum).Sum)-ne10-or$selfTestLines-ne1010-or@($selfTestAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count-ne1){throw '[mir4-m42-02-assurance-release-module-contract]'}
$facadeAst=Get-MIR4M4202AssuranceReleaseAst $sourcePath;$facadeLines=@([IO.File]::ReadAllLines((Join-Path $repo $sourcePath))).Count
if(@($facadeAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count-ne0-or$facadeLines-gt20){throw '[mir4-m42-02-assurance-release-facade]'}
$oldTokens=$null;$oldErrors=$null;$oldAst=[Management.Automation.Language.Parser]::ParseInput($sourceText,[ref]$oldTokens,[ref]$oldErrors)
$oldFunctions=@($oldAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object{$_.Name})
$currentFunctions=@(foreach($spec in $moduleSpecs){(Get-MIR4M4202AssuranceReleaseAst "$moduleRoot/$($spec.name)").FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object{$_.Name}};@($selfTestAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object{$_.Name}))
$oldProjectionSha=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $oldFunctions);$currentProjectionSha=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $currentFunctions)
if($oldFunctions.Count-ne11-or($oldFunctions-join'|')-cne($currentFunctions-join'|')-or$oldProjectionSha-cne$currentProjectionSha){throw '[mir4-m42-02-assurance-release-public-contract]'}
$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
if([int]$inventory.command_count-ne85-or[int]$inventory.summary.unknown-ne0-or[int]$inventory.summary.duplicate_command_keys-ne0){throw '[mir4-m42-02-assurance-release-inventory]'}
$evolvedPaths=@(
  '.mir/assurance.json','.mir/control/paths.yml','.mir/modules.yml','.mir/test-impact.yml','assurance/catalog/tests.json','docs/architecture/module-boundaries.md','governance/automation/mir4-command-inventory-v1.json','scripts/Invoke-MIRAssurance.ps1',
  'tests/architecture/Test-MIRArchitecture.ps1','tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1','tests/repository/Test-MIR4RepositoryFixedPoint.ps1','tests/tooling/Test-MIRAssurance.ps1','tests/tooling/Test-MIRVerificationSchemas.ps1',
  'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1','tests/tooling/Test-MIR4PowerShellCommandRouterDecompositionM4202.ps1','tests/tooling/Test-MIR4ValidationRunnerDecompositionM4202.ps1','tests/tooling/Test-MIR4AssuranceEvidenceDecompositionM4202.ps1','tests/tooling/Test-MIR4PreFreezeReleaseDecompositionM4202.ps1','tests/tooling/Test-MIR4BootstrapMaterializationDecompositionM4202.ps1',
  'tools/lib/assurance/Release.ps1','tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1','tools/mir/application/repository/RepositoryFixedPoint.ps1','validation/tests.yml'
)
$evolvedBindings=@($evolvedPaths|ForEach-Object{[pscustomobject][ordered]@{path=$_;previous_sha256=(Get-MIR4M4202AssuranceReleaseGitTextSha256 -Commit $startingCommit -RelativePath $_);current_sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $_));hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}})
$packageSourceSha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receipt=[pscustomobject][ordered]@{
  schema=1;kind='MIR4M4202AssuranceReleaseDecompositionV1';status='M42-02-PS6-ASSURANCE-RELEASE-DECOMPOSED';starting_dev=[pscustomobject][ordered]@{commit=$startingCommit;tree=$startingTree}
  predecessor=[pscustomobject][ordered]@{work_package='M42-02-PS5-BOOTSTRAP-MATERIALIZATION';receipt=$predecessorPath;receipt_sha256=(Get-FileHash -LiteralPath (Join-Path $repo $predecessorPath) -Algorithm SHA256).Hash.ToUpperInvariant();record_sha256=[string]$predecessor.record_sha256;status=[string]$predecessor.status}
  characterization=[pscustomobject][ordered]@{receipt=$characterizationPath;record_sha256=[string]$characterization.record_sha256;path=$sourcePath;sha256=[string]$characterized[0].sha256;lines=[int]$characterized[0].lines;responsibilities=@($characterized[0].responsibilities)}
  current_source=[pscustomobject][ordered]@{commit=$startingCommit;tree=$startingTree;path=$sourcePath;sha256=$sourceSha256;lines=1810;function_count=11;evolution_chain=@()}
  decomposition=[pscustomobject][ordered]@{responsibility='assurance-release';facade=[pscustomobject][ordered]@{path=$sourcePath;previous_sha256=$sourceSha256;current_sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $sourcePath));hash_mode='canonical-text-v1';previous_lines=1810;current_lines=$facadeLines;maximum_lines=20;function_count=0};module_root=$moduleRoot;module_count=$modules.Count;module_maximum_lines=400;modules=$modules;self_test=[pscustomobject][ordered]@{path=$selfTestPath;authority='canonical-executable-test-support';source_lines=[pscustomobject][ordered]@{start=801;end=1810};sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $selfTestPath));hash_mode='canonical-text-v1';lines=$selfTestLines;function_count=1;source_segment_exact=$true};segment_algorithm='exact-current-function-source-slices-v1'}
  public_contract=[pscustomobject][ordered]@{projection_algorithm='ordered-powershell-function-name-list-v1';previous_sha256=$oldProjectionSha;current_sha256=$currentProjectionSha;unchanged=$true;function_count=$currentFunctions.Count;production_function_count=10;self_test_function_count=1;self_test_command_unchanged=$true}
  semantic_contract=[pscustomobject][ordered]@{source_segments_exact=$true;function_names_and_order_unchanged=$true;module_load_order_explicit=$true;candidate_planning_unchanged=$true;candidate_authority_unchanged=$true;seal_creation_unchanged=$true;seal_verification_unchanged=$true;embedded_self_test_removed_from_release_authority=$true;self_test_loaded_only_for_self_test_command=$true;pre_freeze_authority_chain_extended_for_ps6=$true}
  tooling_inventory=[pscustomobject][ordered]@{path='governance/automation/mir4-command-inventory-v1.json';sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo 'governance/automation/mir4-command-inventory-v1.json'));hash_mode='canonical-text-v1';digest=[string]$inventory.digest;command_count=[int]$inventory.command_count;unknown=[int]$inventory.summary.unknown;duplicate_command_keys=[int]$inventory.summary.duplicate_command_keys}
  evolved_bindings=$evolvedBindings;preservation=[pscustomobject][ordered]@{package_source_sha256=$packageSourceSha256;package_visible_delta=@();gameplay=$false;saves=$true;settings=$true;migrations=$true;compatibility_claims=$true}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false};next_fixed_point='M42-02-PS7-COMPATIBILITY-AUDIT';record_sha256=''
}
$receipt.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $receipt;$json=ConvertTo-MIR4M4202AssuranceReleaseJson $receipt
if(-not($json|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-assurance-release-decomposition-v1.schema.json'))){throw '[mir4-m42-02-assurance-release-receipt-schema]'}
Set-MIR4M4202AssuranceReleaseProjection -RelativePath 'releases/migrations/MIR4-M42-02-Assurance-Release-DecompositionV1.json' -Text $json
$receipt
