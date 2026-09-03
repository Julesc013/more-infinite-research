[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function ConvertTo-MIR4M4202ValidationRunnerJson($Record){
  (($Record|ConvertTo-Json -Depth 100).Replace(([string][char]13+[char]10),[string][char]10)+[string][char]10)
}

function Set-MIR4M4202ValidationRunnerProjection([string]$RelativePath,[string]$Json){
  $path=Join-Path $repo $RelativePath
  if($Check){
    $actual=if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::ReadAllText($path).Replace(([string][char]13+[char]10),[string][char]10)}else{''}
    if($actual-cne$Json){throw "[mir4-m42-02-validation-runner-stale] $RelativePath"}
    return
  }
  [IO.File]::WriteAllText($path,$Json,[Text.UTF8Encoding]::new($false))
}

function Get-MIR4M4202ValidationRunnerAst([string]$RelativePath){
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $RelativePath),[ref]$tokens,[ref]$errors)
  if(@($errors).Count-ne0){throw "[mir4-m42-02-validation-runner-parse] $RelativePath"}
  $ast
}

function Get-MIR4M4202GitText([string]$Commit,[string]$RelativePath){
  $start=[Diagnostics.ProcessStartInfo]::new()
  $start.FileName='git'
  $start.UseShellExecute=$false
  $start.RedirectStandardOutput=$true
  $start.RedirectStandardError=$true
  [void]$start.ArgumentList.Add('-C');[void]$start.ArgumentList.Add($repo)
  [void]$start.ArgumentList.Add('show');[void]$start.ArgumentList.Add("${Commit}:$RelativePath")
  $process=[Diagnostics.Process]::Start($start)
  $text=$process.StandardOutput.ReadToEnd()
  $errorText=$process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if($process.ExitCode-ne0){throw "[mir4-m42-02-validation-runner-git-source] $Commit|$RelativePath|$errorText"}
  $text.Replace("`r`n","`n").Replace("`r","`n")
}

function Get-MIR4M4202GitLines([string]$Commit,[string]$RelativePath){
  $text=Get-MIR4M4202GitText -Commit $Commit -RelativePath $RelativePath
  if(-not$text.EndsWith([string][char]10)){throw "[mir4-m42-02-validation-runner-git-newline] $Commit|$RelativePath"}
  @($text.Split([char]10))
}

function Get-MIR4M4202GitTextSha256([string]$Commit,[string]$RelativePath){
  Get-MIR4Sha256String -Value (Get-MIR4M4202GitText -Commit $Commit -RelativePath $RelativePath)
}

function Get-MIR4M4202Slice([string[]]$Lines,[int]$Start,[int]$End){
  @($Lines[($Start-1)..($End-1)])
}

function Get-MIR4M4202ExpectedModuleText([string]$Name,[string[]]$SourceLines,[int]$Start,[int]$End){
  $lines=[Collections.Generic.List[string]]::new()
  foreach($line in (Get-MIR4M4202Slice -Lines $SourceLines -Start $Start -End $End)){[void]$lines.Add($line)}
  if($Name-ceq'Bootstrap.ps1'){
    for($i=0;$i-lt$lines.Count;$i++){
      if($lines[$i]-ceq'  exit 0'){
        $lines[$i]='  $validationRunnerCompleted = $true'
        $lines.Insert($i+1,'  return')
        $i++
      }
    }
    $listReturn=-1
    for($i=1;$i-lt$lines.Count;$i++){
      if($lines[$i]-ceq'  return'-and$lines[$i-1]-like'  $listed.records*'){$listReturn=$i;break}
    }
    if($listReturn-lt0){throw '[mir4-m42-02-validation-runner-list-return]'}
    $lines.Insert($listReturn,'  $validationRunnerCompleted = $true')
  }
  if($Name-ceq'DefaultCampaign00.ps1'){
    $returnIndex=$lines.FindIndex([Predicate[string]]{param($line)$line-ceq'  return'})
    if($returnIndex-lt0){throw '[mir4-m42-02-validation-runner-reduced-return]'}
    $lines.Insert($returnIndex,'  $validationCampaignCompleted = $true')
  }
  (($lines.ToArray()-join[char]10)+[char]10)
}

$startingCommit='bb953b617c823a4834fc211735f8312cce1ef48e'
$startingTree='6946cf5125a8b21af46757164834d5583647098a'
$predecessorPath='releases/migrations/MIR4-M42-02-PowerShell-Command-Router-DecompositionV1.json'
$predecessorRaw=Get-Content -Raw -LiteralPath (Join-Path $repo $predecessorPath)
$predecessor=$predecessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$predecessor.status-cne'M42-02-PS1-COMMAND-ROUTER-DECOMPOSED'-or[string]$predecessor.next_fixed_point-cne'M42-02-PS2-VALIDATION-RUNNER'){throw '[mir4-m42-02-validation-runner-predecessor]'}

$characterizationPath='releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
$characterization=Get-Content -Raw -LiteralPath (Join-Path $repo $characterizationPath)|ConvertFrom-Json -Depth 100 -DateKind String
$characterized=@($characterization.tracked_files|Where-Object{[string]$_.path-ceq'scripts/Invoke-MIRValidation.ps1'})
if($characterized.Count-ne1-or[string]$characterized[0].sha256-cne'29961C5D5EFA6B241C2F4A4DDF3AC485867ACC7C6D17E312F30704DD04A2BEBB'){throw '[mir4-m42-02-validation-runner-characterization]'}

$sourceLines=Get-MIR4M4202GitLines -Commit $startingCommit -RelativePath 'scripts/Invoke-MIRValidation.ps1'
if($sourceLines.Count-ne5159-or(Get-MIR4Sha256String -Value ($sourceLines-join[char]10))-cne[string]$characterized[0].sha256){throw '[mir4-m42-02-validation-runner-starting-source]'}

$moduleSpecs=@(
  [pscustomobject]@{name='Bootstrap.ps1';role='target bootstrap and early modes';start=34;end=200},
  [pscustomobject]@{name='StaticCore.ps1';role='core repository static checks';start=202;end=713},
  [pscustomobject]@{name='StaticFixtureMods.ps1';role='fixture metadata checks';start=714;end=827},
  [pscustomobject]@{name='StaticSciencePackSettings.ps1';role='science and settings static checks';start=828;end=1381},
  [pscustomobject]@{name='StaticPrototypeLimits.ps1';role='prototype-limit static checks';start=1382;end=1501},
  [pscustomobject]@{name='StaticCompatibilityTooling.ps1';role='compatibility-tooling static checks';start=1502;end=1741},
  [pscustomobject]@{name='StaticCompilerDiagnostics.ps1';role='compiler and compatibility static checks';start=1742;end=2103},
  [pscustomobject]@{name='StaticPolicyAndDocs.ps1';role='policy and release-document checks';start=2104;end=2289},
  [pscustomobject]@{name='StaticPackage.ps1';role='package identity and determinism checks';start=2290;end=2506},
  [pscustomobject]@{name='RuntimeSelection.ps1';role='runtime scenario selection';start=2508;end=2637},
  [pscustomobject]@{name='RuntimeWorkspace.ps1';role='runtime result and workspace setup';start=2638;end=2770},
  [pscustomobject]@{name='RuntimeScenarioSetup.ps1';role='runtime fixture and configuration setup';start=2771;end=2987},
  [pscustomobject]@{name='RuntimeExecution.ps1';role='Factorio scenario execution';start=2988;end=3243},
  [pscustomobject]@{name='RuntimeAssertions.ps1';role='runtime log and report assertions';start=3244;end=3506},
  [pscustomobject]@{name='PackageSmoke.ps1';role='exact package smoke policy';start=3507;end=3667},
  [pscustomobject]@{name='DefaultCampaign00.ps1';role='package and reduced-target campaign';start=3935;end=4022},
  [pscustomobject]@{name='DefaultCampaign01.ps1';role='base compiler campaign part one';start=4024;end=4338},
  [pscustomobject]@{name='DefaultCampaign02.ps1';role='base and settings campaign part two';start=4339;end=4632},
  [pscustomobject]@{name='DefaultCampaign03.ps1';role='scripted and Space Age campaign';start=4633;end=4885},
  [pscustomobject]@{name='CheckpointCampaign.ps1';role='checkpoint-resumable native-owner campaign';start=4890;end=4977},
  [pscustomobject]@{name='FinalCampaign.ps1';role='final policy and negative scenarios';start=4979;end=5148}
)
$moduleRoot='tools/lib/validation/runner'
$modules=@(foreach($spec in $moduleSpecs){
  $relative="$moduleRoot/$($spec.name)"
  $expected=Get-MIR4M4202ExpectedModuleText -Name $spec.name -SourceLines $sourceLines -Start $spec.start -End $spec.end
  $actual=[IO.File]::ReadAllText((Join-Path $repo $relative)).Replace("`r`n","`n").Replace("`r","`n")
  if($actual-cne$expected){throw "[mir4-m42-02-validation-runner-segment] $relative"}
  $ast=Get-MIR4M4202ValidationRunnerAst $relative
  $lineCount=@([IO.File]::ReadAllLines((Join-Path $repo $relative))).Count
  if($lineCount-gt600){throw "[mir4-m42-02-validation-runner-module-size] $relative|$lineCount"}
  [pscustomobject][ordered]@{path=$relative;role=[string]$spec.role;source_lines=[pscustomobject][ordered]@{start=[int]$spec.start;end=[int]$spec.end};sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $relative));hash_mode='canonical-text-v1';lines=$lineCount;function_count=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count;parse_errors=0}
})
if($modules.Count-ne21){throw '[mir4-m42-02-validation-runner-module-count]'}

$facadePath='scripts/Invoke-MIRValidation.ps1'
$facadeAst=Get-MIR4M4202ValidationRunnerAst $facadePath
$facadeLines=@([IO.File]::ReadAllLines((Join-Path $repo $facadePath))).Count
$expectedFacade=((Get-MIR4M4202Slice -Lines $sourceLines -Start 1 -End 22)-join[char]10)+[char]10+[char]10+'. (Join-Path $PSScriptRoot "../tools/lib/validation/runner/Invoke-MIRValidationRunner.ps1")'+[char]10
$actualFacade=[IO.File]::ReadAllText((Join-Path $repo $facadePath)).Replace("`r`n","`n").Replace("`r","`n")
if($actualFacade-cne$expectedFacade-or$facadeLines-gt40-or$facadeAst.ParamBlock.Parameters.Count-ne18){throw '[mir4-m42-02-validation-runner-facade]'}
$oldTokens=$null;$oldErrors=$null;$oldAst=[Management.Automation.Language.Parser]::ParseInput(($sourceLines-join[char]10),[ref]$oldTokens,[ref]$oldErrors)
$oldParameters=$oldAst.ParamBlock.Extent.Text.Replace("`r`n","`n").Replace("`r","`n")
$currentParameters=$facadeAst.ParamBlock.Extent.Text.Replace("`r`n","`n").Replace("`r","`n")
if($currentParameters-cne$oldParameters){throw '[mir4-m42-02-validation-runner-parameters]'}
$parameterSha256=Get-MIR4Sha256String -Value $currentParameters

$applicationPath="$moduleRoot/Invoke-MIRValidationRunner.ps1"
$applicationAst=Get-MIR4M4202ValidationRunnerAst $applicationPath
$applicationText=[IO.File]::ReadAllText((Join-Path $repo $applicationPath)).Replace("`r`n","`n").Replace("`r","`n")
$selectedPayload=((Get-MIR4M4202Slice -Lines $sourceLines -Start 3668 -End 3931)-join[char]10)+[char]10
if(-not$applicationText.Contains($selectedPayload)){throw '[mir4-m42-02-validation-runner-selected-payload]'}
$applicationLines=@([IO.File]::ReadAllLines((Join-Path $repo $applicationPath))).Count
if($applicationLines-gt400){throw '[mir4-m42-02-validation-runner-application-size]'}

$runtimeRegistryPath='validation/scenarios/runtime.json'
$runtimeRegistry=Get-Content -Raw -LiteralPath (Join-Path $repo $runtimeRegistryPath)|ConvertFrom-Json -Depth 100
$profileCounts=[pscustomobject][ordered]@{f210=@($runtimeRegistry.profiles.'2.1').Count;f200=@($runtimeRegistry.profiles.'2.0').Count;f110=@($runtimeRegistry.profiles.'1.1').Count;f100=@($runtimeRegistry.profiles.'1.0').Count}
if($profileCounts.f210-ne135-or$profileCounts.f200-ne7-or$profileCounts.f110-ne4-or$profileCounts.f100-ne4){throw '[mir4-m42-02-validation-runner-scenarios]'}

$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
if([int]$inventory.command_count-ne85-or[int]$inventory.summary.unknown-ne0-or[int]$inventory.summary.duplicate_command_keys-ne0){throw '[mir4-m42-02-validation-runner-inventory]'}

$evolvedPaths=@(
  '.mir/assurance.json','.mir/control/paths.yml','.mir/modules.yml','.mir/test-impact.yml','assurance/catalog/tests.json',
  'docs/architecture/module-boundaries.md','governance/automation/mir4-command-inventory-v1.json','scripts/Invoke-MIRValidation.ps1',
  'tests/architecture/Test-MIRArchitecture.ps1','tests/repository/Test-MIR4RepositoryFixedPoint.ps1',
  'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1','tests/tooling/Test-MIR4PowerShellCommandRouterDecompositionM4202.ps1',
  'tests/tooling/Test-MIRAssurance.ps1','tools/lib/mir4/PreFreezeRelease.ps1','tools/mir/application/repository/RepositoryFixedPoint.ps1','validation/tests.yml'
)
$evolvedBindings=@($evolvedPaths|ForEach-Object{[pscustomobject][ordered]@{path=$_;previous_sha256=(Get-MIR4M4202GitTextSha256 -Commit $startingCommit -RelativePath $_);current_sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $_));hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}})

$packageSourceSha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receipt=[pscustomobject][ordered]@{
  schema=1;kind='MIR4M4202ValidationRunnerDecompositionV1';status='M42-02-PS2-VALIDATION-RUNNER-DECOMPOSED'
  starting_dev=[pscustomobject][ordered]@{commit=$startingCommit;tree=$startingTree}
  predecessor=[pscustomobject][ordered]@{work_package='M42-02-PS1-COMMAND-ROUTER';receipt=$predecessorPath;receipt_sha256=(Get-FileHash -LiteralPath (Join-Path $repo $predecessorPath) -Algorithm SHA256).Hash.ToUpperInvariant();record_sha256=[string]$predecessor.record_sha256;status=[string]$predecessor.status}
  characterization=[pscustomobject][ordered]@{receipt=$characterizationPath;record_sha256=[string]$characterization.record_sha256;path='scripts/Invoke-MIRValidation.ps1';sha256=[string]$characterized[0].sha256;lines=[int]$characterized[0].lines;responsibilities=@($characterized[0].responsibilities)}
  decomposition=[pscustomobject][ordered]@{responsibility='validation-runner';facade=[pscustomobject][ordered]@{path=$facadePath;previous_sha256=[string]$characterized[0].sha256;current_sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $facadePath));hash_mode='canonical-text-v1';previous_lines=5159;current_lines=$facadeLines;maximum_lines=40;parameter_count=18};application=[pscustomobject][ordered]@{path=$applicationPath;sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $applicationPath));hash_mode='canonical-text-v1';lines=$applicationLines;maximum_lines=400;parse_errors=0};module_root=$moduleRoot;module_count=$modules.Count;module_maximum_lines=600;modules=$modules;segment_algorithm='exact-canonical-source-slices-with-explicit-early-completion-handoffs-v1'}
  public_contract=[pscustomobject][ordered]@{parameter_projection_algorithm='powershell-param-block-canonical-text-v1';previous_sha256=$parameterSha256;current_sha256=$parameterSha256;unchanged=$true;parameter_count=18;list_mode=$true;docs_only=$true;manifests_only=$true;architecture_only=$true;static_only=$true;scenario_worker=$true}
  semantic_contract=[pscustomobject][ordered]@{runtime_registry=[pscustomobject][ordered]@{path=$runtimeRegistryPath;sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $runtimeRegistryPath));hash_mode='canonical-text-v1';profile_counts=$profileCounts};selected_runtime_payload_sha256=(Get-MIR4Sha256String -Value $selectedPayload);source_segments_exact=$true;scenario_names_and_groups_unchanged=$true;schema_2_result_contract_unchanged=$true;factorio_process_owner='tools/lib/validation/FactorioProcess.ps1';result_owner='tools/lib/validation/ResultAggregation.ps1'}
  tooling_inventory=[pscustomobject][ordered]@{path='governance/automation/mir4-command-inventory-v1.json';sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo 'governance/automation/mir4-command-inventory-v1.json'));hash_mode='canonical-text-v1';digest=[string]$inventory.digest;command_count=[int]$inventory.command_count;unknown=[int]$inventory.summary.unknown;duplicate_command_keys=[int]$inventory.summary.duplicate_command_keys}
  evolved_bindings=$evolvedBindings
  preservation=[pscustomobject][ordered]@{package_source_sha256=$packageSourceSha256;package_visible_delta=@();gameplay=$false;saves=$true;settings=$true;migrations=$true;compatibility_claims=$true}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  next_fixed_point='M42-02-PS3-ASSURANCE-EVIDENCE';record_sha256=''
}
$receipt.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $receipt
$json=ConvertTo-MIR4M4202ValidationRunnerJson $receipt
if(-not($json|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-validation-runner-decomposition-v1.schema.json'))){throw '[mir4-m42-02-validation-runner-receipt-schema]'}
Set-MIR4M4202ValidationRunnerProjection -RelativePath 'releases/migrations/MIR4-M42-02-Validation-Runner-DecompositionV1.json' -Json $json
$receipt
