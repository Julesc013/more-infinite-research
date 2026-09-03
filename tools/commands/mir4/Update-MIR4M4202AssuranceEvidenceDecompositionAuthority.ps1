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

function ConvertTo-MIR4M4202AssuranceEvidenceJson($Record){
  (($Record|ConvertTo-Json -Depth 100).Replace(([string][char]13+[char]10),[string][char]10)+[string][char]10)
}

function Set-MIR4M4202AssuranceEvidenceProjection([string]$RelativePath,[string]$Json){
  $path=Join-Path $repo $RelativePath
  if($Check){
    $actual=if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::ReadAllText($path).Replace(([string][char]13+[char]10),[string][char]10)}else{''}
    if($actual-cne$Json){throw "[mir4-m42-02-assurance-evidence-stale] $RelativePath"}
    return
  }
  [IO.File]::WriteAllText($path,$Json,[Text.UTF8Encoding]::new($false))
}

function Get-MIR4M4202AssuranceEvidenceAst([string]$RelativePath){
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $RelativePath),[ref]$tokens,[ref]$errors)
  if(@($errors).Count-ne0){throw "[mir4-m42-02-assurance-evidence-parse] $RelativePath"}
  $ast
}

function Get-MIR4M4202AssuranceEvidenceGitText([string]$Commit,[string]$RelativePath){
  $start=[Diagnostics.ProcessStartInfo]::new()
  $start.FileName='git';$start.UseShellExecute=$false;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  [void]$start.ArgumentList.Add('-C');[void]$start.ArgumentList.Add($repo);[void]$start.ArgumentList.Add('show');[void]$start.ArgumentList.Add("${Commit}:$RelativePath")
  $process=[Diagnostics.Process]::Start($start)
  $text=$process.StandardOutput.ReadToEnd();$errorText=$process.StandardError.ReadToEnd();$process.WaitForExit()
  if($process.ExitCode-ne0){throw "[mir4-m42-02-assurance-evidence-git-source] $Commit|$RelativePath|$errorText"}
  $text.Replace("`r`n","`n").Replace("`r","`n")
}

function Get-MIR4M4202AssuranceEvidenceGitLines([string]$Commit,[string]$RelativePath){
  $text=Get-MIR4M4202AssuranceEvidenceGitText -Commit $Commit -RelativePath $RelativePath
  if(-not$text.EndsWith([string][char]10)){throw "[mir4-m42-02-assurance-evidence-git-newline] $Commit|$RelativePath"}
  @($text.Split([char]10))
}

function Get-MIR4M4202AssuranceEvidenceGitTextSha256([string]$Commit,[string]$RelativePath){
  Get-MIR4Sha256String -Value (Get-MIR4M4202AssuranceEvidenceGitText -Commit $Commit -RelativePath $RelativePath)
}

function Get-MIR4M4202AssuranceEvidenceSlice([string[]]$Lines,[int]$Start,[int]$End){
  @($Lines[($Start-1)..($End-1)])
}

$startingCommit='0af660065bd238a506b7c77d55fff9a04d64fa4e'
$startingTree='a214cf26600cee0bfd64128f4bd80e2749572f6a'
$predecessorPath='releases/migrations/MIR4-M42-02-Validation-Runner-DecompositionV1.json'
$predecessor=Get-Content -Raw -LiteralPath (Join-Path $repo $predecessorPath)|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$predecessor.status-cne'M42-02-PS2-VALIDATION-RUNNER-DECOMPOSED'-or[string]$predecessor.next_fixed_point-cne'M42-02-PS3-ASSURANCE-EVIDENCE'){throw '[mir4-m42-02-assurance-evidence-predecessor]'}

$characterizationPath='releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
$characterization=Get-Content -Raw -LiteralPath (Join-Path $repo $characterizationPath)|ConvertFrom-Json -Depth 100 -DateKind String
$characterized=@($characterization.tracked_files|Where-Object{[string]$_.path-ceq'tools/lib/assurance/Evidence.ps1'})
if($characterized.Count-ne1-or[string]$characterized[0].sha256-cne'1464AD8A30778F2E768FBE363DF107F1D7E10E7671A7E583F3B4A25584B19D6A'){throw '[mir4-m42-02-assurance-evidence-characterization]'}

$sourcePath='tools/lib/assurance/Evidence.ps1'
$sourceLines=Get-MIR4M4202AssuranceEvidenceGitLines -Commit $startingCommit -RelativePath $sourcePath
if($sourceLines.Count-ne2650-or(Get-MIR4Sha256String -Value ($sourceLines-join[char]10))-cne[string]$characterized[0].sha256){throw '[mir4-m42-02-assurance-evidence-starting-source]'}
$moduleSpecs=@(
  [pscustomobject]@{name='Fingerprints.ps1';role='input and test fingerprints';start=1;end=564},
  [pscustomobject]@{name='ProducerTrust.ps1';role='repository identity, producers, trust, and capsule digest';start=566;end=768},
  [pscustomobject]@{name='WorkerArtifactValidation.ps1';role='capsule, pointer, path, and artifact-tree validation';start=770;end=1037},
  [pscustomobject]@{name='WorkerImport.ps1';role='worker receipts, content-addressed objects, and deterministic import';start=1039;end=1518},
  [pscustomobject]@{name='EvidenceDecisions.ps1';role='reusable, checkpoint, running, and disposition decisions';start=1520;end=1700},
  [pscustomobject]@{name='AttemptState.ps1';role='running markers and append-only attempts';start=1702;end=1775},
  [pscustomobject]@{name='CommandExecution.ps1';role='command reconstruction and execution';start=1777;end=1884},
  [pscustomobject]@{name='Plans.ps1';role='plan decisions, material, completion, reconstruction, and freshness';start=1886;end=2123},
  [pscustomobject]@{name='ExecutionAndGate.ps1';role='waiting, artifacts, test and plan execution, aggregate gate, and build results';start=2125;end=2649}
)
$moduleRoot='tools/lib/assurance/evidence'
$modules=@(foreach($spec in $moduleSpecs){
  $relative="$moduleRoot/$($spec.name)"
  $expected=((Get-MIR4M4202AssuranceEvidenceSlice -Lines $sourceLines -Start $spec.start -End $spec.end)-join[char]10)+[char]10
  $actual=[IO.File]::ReadAllText((Join-Path $repo $relative)).Replace("`r`n","`n").Replace("`r","`n")
  if($actual-cne$expected){throw "[mir4-m42-02-assurance-evidence-segment] $relative"}
  $ast=Get-MIR4M4202AssuranceEvidenceAst $relative
  $lineCount=@([IO.File]::ReadAllLines((Join-Path $repo $relative))).Count
  if($lineCount-gt600){throw "[mir4-m42-02-assurance-evidence-module-size] $relative|$lineCount"}
  [pscustomobject][ordered]@{path=$relative;role=[string]$spec.role;source_lines=[pscustomobject][ordered]@{start=[int]$spec.start;end=[int]$spec.end};sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $relative));hash_mode='canonical-text-v1';lines=$lineCount;function_count=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count;parse_errors=0}
})
if($modules.Count-ne9-or(@($modules|Measure-Object function_count -Sum).Sum)-ne62){throw '[mir4-m42-02-assurance-evidence-module-contract]'}

$facadeAst=Get-MIR4M4202AssuranceEvidenceAst $sourcePath
$facadeLines=@([IO.File]::ReadAllLines((Join-Path $repo $sourcePath))).Count
$expectedFacade=(($moduleSpecs|ForEach-Object{". (Join-Path `$PSScriptRoot 'evidence/$($_.name)')"})-join[char]10)+[char]10
$actualFacade=[IO.File]::ReadAllText((Join-Path $repo $sourcePath)).Replace("`r`n","`n").Replace("`r","`n")
if($actualFacade-cne$expectedFacade-or$facadeLines-gt20-or@($facadeAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count-ne0){throw '[mir4-m42-02-assurance-evidence-facade]'}

$oldTokens=$null;$oldErrors=$null
$oldAst=[Management.Automation.Language.Parser]::ParseInput(($sourceLines-join[char]10),[ref]$oldTokens,[ref]$oldErrors)
$oldFunctions=@($oldAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object{$_.Name})
$currentFunctions=@(foreach($spec in $moduleSpecs){(Get-MIR4M4202AssuranceEvidenceAst "$moduleRoot/$($spec.name)").FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object{$_.Name}})
$oldProjectionSha=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $oldFunctions)
$currentProjectionSha=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $currentFunctions)
if($oldFunctions.Count-ne62-or($oldFunctions-join'|')-cne($currentFunctions-join'|')-or$oldProjectionSha-cne$currentProjectionSha){throw '[mir4-m42-02-assurance-evidence-public-contract]'}

$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
if([int]$inventory.command_count-ne85-or[int]$inventory.summary.unknown-ne0-or[int]$inventory.summary.duplicate_command_keys-ne0){throw '[mir4-m42-02-assurance-evidence-inventory]'}
$evolvedPaths=@(
  '.mir/assurance.json','.mir/control/paths.yml','.mir/modules.yml','.mir/test-impact.yml','assurance/catalog/tests.json',
  'docs/architecture/module-boundaries.md','governance/automation/mir4-command-inventory-v1.json',
  'tests/architecture/Test-MIRArchitecture.ps1','tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1','tests/repository/Test-MIR4RepositoryFixedPoint.ps1',
  'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1','tests/tooling/Test-MIR4PowerShellCommandRouterDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4ValidationRunnerDecompositionM4202.ps1','tests/tooling/Test-MIRAssurance.ps1','tests/tooling/Test-MIRVerificationSchemas.ps1',
  'tools/lib/mir4/PreFreezeRelease.ps1','tools/mir/application/repository/RepositoryFixedPoint.ps1','validation/tests.yml'
)
$evolvedBindings=@($evolvedPaths|ForEach-Object{[pscustomobject][ordered]@{path=$_;previous_sha256=(Get-MIR4M4202AssuranceEvidenceGitTextSha256 -Commit $startingCommit -RelativePath $_);current_sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $_));hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}})

$packageSourceSha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receipt=[pscustomobject][ordered]@{
  schema=1;kind='MIR4M4202AssuranceEvidenceDecompositionV1';status='M42-02-PS3-ASSURANCE-EVIDENCE-DECOMPOSED'
  starting_dev=[pscustomobject][ordered]@{commit=$startingCommit;tree=$startingTree}
  predecessor=[pscustomobject][ordered]@{work_package='M42-02-PS2-VALIDATION-RUNNER';receipt=$predecessorPath;receipt_sha256=(Get-FileHash -LiteralPath (Join-Path $repo $predecessorPath) -Algorithm SHA256).Hash.ToUpperInvariant();record_sha256=[string]$predecessor.record_sha256;status=[string]$predecessor.status}
  characterization=[pscustomobject][ordered]@{receipt=$characterizationPath;record_sha256=[string]$characterization.record_sha256;path=$sourcePath;sha256=[string]$characterized[0].sha256;lines=[int]$characterized[0].lines;responsibilities=@($characterized[0].responsibilities)}
  decomposition=[pscustomobject][ordered]@{responsibility='assurance-evidence';facade=[pscustomobject][ordered]@{path=$sourcePath;previous_sha256=[string]$characterized[0].sha256;current_sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $sourcePath));hash_mode='canonical-text-v1';previous_lines=2650;current_lines=$facadeLines;maximum_lines=20;function_count=0};module_root=$moduleRoot;module_count=$modules.Count;module_maximum_lines=600;modules=$modules;segment_algorithm='exact-canonical-function-source-slices-v1'}
  public_contract=[pscustomobject][ordered]@{projection_algorithm='ordered-powershell-function-name-list-v1';previous_sha256=$oldProjectionSha;current_sha256=$currentProjectionSha;unchanged=$true;function_count=$currentFunctions.Count}
  semantic_contract=[pscustomobject][ordered]@{source_segments_exact=$true;function_names_and_order_unchanged=$true;module_load_order_explicit=$true;fingerprints_unchanged=$true;producer_trust_unchanged=$true;worker_ingestion_unchanged=$true;reuse_and_attempt_state_unchanged=$true;command_execution_unchanged=$true;plans_and_gates_unchanged=$true;result_schema='mir-test-result-v1';worker_receipt_schema='mir-assurance-worker-receipt-v3'}
  tooling_inventory=[pscustomobject][ordered]@{path='governance/automation/mir4-command-inventory-v1.json';sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo 'governance/automation/mir4-command-inventory-v1.json'));hash_mode='canonical-text-v1';digest=[string]$inventory.digest;command_count=[int]$inventory.command_count;unknown=[int]$inventory.summary.unknown;duplicate_command_keys=[int]$inventory.summary.duplicate_command_keys}
  evolved_bindings=$evolvedBindings
  preservation=[pscustomobject][ordered]@{package_source_sha256=$packageSourceSha256;package_visible_delta=@();gameplay=$false;saves=$true;settings=$true;migrations=$true;compatibility_claims=$true}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  next_fixed_point='M42-02-PS4-PRE-FREEZE-RELEASE';record_sha256=''
}
$receipt.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $receipt
$json=ConvertTo-MIR4M4202AssuranceEvidenceJson $receipt
if(-not($json|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-assurance-evidence-decomposition-v1.schema.json'))){throw '[mir4-m42-02-assurance-evidence-receipt-schema]'}
Set-MIR4M4202AssuranceEvidenceProjection -RelativePath 'releases/migrations/MIR4-M42-02-Assurance-Evidence-DecompositionV1.json' -Json $json
$receipt
