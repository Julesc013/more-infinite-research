[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,[switch]$Check)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function ConvertTo-MIR4M4202PreFreezeReleaseJson($Record){(($Record|ConvertTo-Json -Depth 100).Replace(([string][char]13+[char]10),[string][char]10)+[string][char]10)}
function Set-MIR4M4202PreFreezeReleaseProjection([string]$RelativePath,[string]$Text){
  $path=Join-Path $repo $RelativePath
  if($Check){
    $actual=if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::ReadAllText($path).Replace("`r`n","`n").Replace("`r","`n")}else{''}
    if($actual-cne$Text){throw "[mir4-m42-02-pre-freeze-release-stale] $RelativePath"}
    return
  }
  $parent=Split-Path -Parent $path
  if(-not(Test-Path -LiteralPath $parent -PathType Container)){[void](New-Item -ItemType Directory -Path $parent)}
  [IO.File]::WriteAllText($path,$Text,[Text.UTF8Encoding]::new($false))
}
function Get-MIR4M4202PreFreezeReleaseAst([string]$RelativePath){
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $RelativePath),[ref]$tokens,[ref]$errors)
  if(@($errors).Count-ne0){throw "[mir4-m42-02-pre-freeze-release-parse] $RelativePath"}
  $ast
}
function Get-MIR4M4202PreFreezeReleaseGitText([string]$Commit,[string]$RelativePath){
  $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName='git';$start.UseShellExecute=$false;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  [void]$start.ArgumentList.Add('-C');[void]$start.ArgumentList.Add($repo);[void]$start.ArgumentList.Add('show');[void]$start.ArgumentList.Add("${Commit}:$RelativePath")
  $process=[Diagnostics.Process]::Start($start);$text=$process.StandardOutput.ReadToEnd();$errorText=$process.StandardError.ReadToEnd();$process.WaitForExit()
  if($process.ExitCode-ne0){throw "[mir4-m42-02-pre-freeze-release-git-source] $Commit|$RelativePath|$errorText"}
  $text.Replace("`r`n","`n").Replace("`r","`n")
}
function Get-MIR4M4202PreFreezeReleaseGitTextSha256([string]$Commit,[string]$RelativePath){Get-MIR4Sha256String -Value (Get-MIR4M4202PreFreezeReleaseGitText -Commit $Commit -RelativePath $RelativePath)}
function Get-MIR4M4202PreFreezeReleaseSlice([string[]]$Lines,[int]$Start,[int]$End){@($Lines[($Start-1)..($End-1)])}

$startingCommit='dc3a02302e5091010b8369ab314299b65522187e';$startingTree='e95dc0118a475edd273c5a58accd462918faa8c6'
$predecessorPath='releases/migrations/MIR4-M42-02-Assurance-Evidence-DecompositionV1.json'
$predecessor=Get-Content -Raw -LiteralPath (Join-Path $repo $predecessorPath)|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$predecessor.status-cne'M42-02-PS3-ASSURANCE-EVIDENCE-DECOMPOSED'-or[string]$predecessor.next_fixed_point-cne'M42-02-PS4-PRE-FREEZE-RELEASE'){throw '[mir4-m42-02-pre-freeze-release-predecessor]'}
$characterizationPath='releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
$characterization=Get-Content -Raw -LiteralPath (Join-Path $repo $characterizationPath)|ConvertFrom-Json -Depth 100 -DateKind String
$characterized=@($characterization.tracked_files|Where-Object{[string]$_.path-ceq'tools/lib/mir4/PreFreezeRelease.ps1'})
if($characterized.Count-ne1-or[string]$characterized[0].sha256-cne'1D21940B53412C4878B2E984C4C54F5BE81FDEC2FCD8E734D388FE8B966F2181'){throw '[mir4-m42-02-pre-freeze-release-characterization]'}
$sourcePath='tools/lib/mir4/PreFreezeRelease.ps1'
$sourceText=Get-MIR4M4202PreFreezeReleaseGitText -Commit $startingCommit -RelativePath $sourcePath
$sourceSha256=Get-MIR4Sha256String -Value $sourceText;$sourceLines=@($sourceText.Split([char]10))
if(-not$sourceText.EndsWith([string][char]10)-or$sourceSha256-cne'EF715051266F0984B7A57C1F61497E0FB614E2AB28F80EFE5A56D2350CB9C89E'-or$sourceLines.Count-ne2284){throw '[mir4-m42-02-pre-freeze-release-starting-source]'}
$moduleSpecs=@(
  [pscustomobject]@{name='Common.ps1';role='shared paths, digests, records, and final-mile candidate authority';start=5;end=202},
  [pscustomobject]@{name='PolicyLocks.ps1';role='ruleset, publisher admission, and production action locks';start=204;end=329},
  [pscustomobject]@{name='AuthorityState.ps1';role='pre-freeze authority-chain state construction';start=331;end=593},
  [pscustomobject]@{name='AuthorityValidation.ps1';role='pre-freeze authority-chain validation';start=595;end=1502},
  [pscustomobject]@{name='ReleaseDoctor.ps1';role='release doctor, workflow maturity, and invocation checks';start=1504;end=1808},
  [pscustomobject]@{name='PlaytestSessions.ps1';role='playtest session creation, capture, comparison, and completion';start=1810;end=2283}
)
$moduleRoot='tools/lib/mir4/pre-freeze-release';$expectedModules=@{}
foreach($spec in $moduleSpecs){
  $relative="$moduleRoot/$($spec.name)";$expected=((Get-MIR4M4202PreFreezeReleaseSlice -Lines $sourceLines -Start $spec.start -End $spec.end)-join[char]10)+[char]10
  if($spec.name-ceq'AuthorityValidation.ps1'){
    $schemaMarker="    '.mir/releases/waves/mir4-r0/MIR4-Maintainer-Final-GitHub-Release-AuthorizationV1.json'"
    $schemaBinding="    'releases/migrations/MIR4-M42-02-Pre-Freeze-Release-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-pre-freeze-release-decomposition-v1.schema.json'`n"
    $schemaIndex=$expected.IndexOf($schemaMarker,[StringComparison]::Ordinal)
    if($schemaIndex-lt0){throw '[mir4-m42-02-pre-freeze-release-schema-marker]'}
    $expected=$expected.Insert($schemaIndex,$schemaBinding)
    $successorMarker='  $staleAuthorityBindings = @()'
    $successorIndex=$expected.IndexOf($successorMarker,[StringComparison]::Ordinal)
    if($successorIndex-lt0){throw '[mir4-m42-02-pre-freeze-release-successor-marker]'}
    $successor=@'
  $preFreezeReleaseReceiptPath = 'releases/migrations/MIR4-M42-02-Pre-Freeze-Release-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $preFreezeReleaseReceiptPath) -PathType Leaf) {
    $preFreezeRelease = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $preFreezeReleaseReceiptPath -Kind 'MIR4M4202PreFreezeReleaseDecompositionV1'
    if ([string]$preFreezeRelease.predecessor.receipt -cne $priorReceiptPath -or
        [string]$preFreezeRelease.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$preFreezeRelease.predecessor.record_sha256 -cne [string]$assuranceEvidence.record_sha256) {
      throw '[mir4-prefreeze-m42-02-pre-freeze-release-predecessor]'
    }
    $preFreezeReleaseEnrollmentBaselines = @{
      'tests/tooling/Test-MIR4AssuranceEvidenceDecompositionM4202.ps1'='FBBB2E0CFB321E0B24A6CA8EA8670487725FBD55D0BC0D1892F8AC01263690F9'
    }
    $preFreezeReleaseEvolvedPaths = @{}
    foreach ($binding in @($preFreezeRelease.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $preFreezeReleaseEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$preFreezeReleaseEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-pre-freeze-release-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $preFreezeReleaseEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-pre-freeze-release-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $preFreezeReleaseEvolvedPaths[$path] = $true
    }
    if ($preFreezeReleaseEvolvedPaths.Count -ne 20 -or
        [string]$preFreezeRelease.status -cne 'M42-02-PS4-PRE-FREEZE-RELEASE-DECOMPOSED' -or
        [string]$preFreezeRelease.decomposition.responsibility -cne 'pre-freeze-release' -or
        [string]$preFreezeRelease.next_fixed_point -cne 'M42-02-PS5-BOOTSTRAP-MATERIALIZATION' -or
        @($preFreezeRelease.decomposition.modules).Count -ne 6 -or
        -not [bool]$preFreezeRelease.public_contract.unchanged -or
        [int]$preFreezeRelease.public_contract.function_count -ne 25 -or
        -not [bool]$preFreezeRelease.semantic_contract.source_segments_exact_except_declared_self_successor -or
        -not [bool]$preFreezeRelease.semantic_contract.declared_self_successor_extension -or
        [string]$preFreezeRelease.preservation.package_source_sha256 -cne (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)) {
      throw '[mir4-prefreeze-m42-02-pre-freeze-release-scope]'
    }
    foreach ($property in $preFreezeRelease.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-pre-freeze-release-transition] $($property.Name)" }
    }
    $priorReceiptPath = $preFreezeReleaseReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
'@
    $successor=$successor.Replace("`r`n","`n")
    $expected=$expected.Insert($successorIndex,$successor)
  }
  $expectedModules[$relative]=$expected;Set-MIR4M4202PreFreezeReleaseProjection -RelativePath $relative -Text $expected
}
$expectedFacade=@"
Set-StrictMode -Version Latest

. (Join-Path `$PSScriptRoot '../../mir/application/release/F210QualificationPolicy.ps1')

. (Join-Path `$PSScriptRoot 'pre-freeze-release/Common.ps1')
. (Join-Path `$PSScriptRoot 'pre-freeze-release/PolicyLocks.ps1')
. (Join-Path `$PSScriptRoot 'pre-freeze-release/AuthorityState.ps1')
. (Join-Path `$PSScriptRoot 'pre-freeze-release/AuthorityValidation.ps1')
. (Join-Path `$PSScriptRoot 'pre-freeze-release/ReleaseDoctor.ps1')
. (Join-Path `$PSScriptRoot 'pre-freeze-release/PlaytestSessions.ps1')
"@.Replace("`r`n","`n")
Set-MIR4M4202PreFreezeReleaseProjection -RelativePath $sourcePath -Text $expectedFacade
$modules=@(foreach($spec in $moduleSpecs){
  $relative="$moduleRoot/$($spec.name)";$actual=[IO.File]::ReadAllText((Join-Path $repo $relative)).Replace("`r`n","`n").Replace("`r","`n")
  if($actual-cne[string]$expectedModules[$relative]){throw "[mir4-m42-02-pre-freeze-release-segment] $relative"}
  $ast=Get-MIR4M4202PreFreezeReleaseAst $relative;$lineCount=@([IO.File]::ReadAllLines((Join-Path $repo $relative))).Count
  if($lineCount-gt1000){throw "[mir4-m42-02-pre-freeze-release-module-size] $relative|$lineCount"}
  [pscustomobject][ordered]@{path=$relative;role=[string]$spec.role;source_lines=[pscustomobject][ordered]@{start=[int]$spec.start;end=[int]$spec.end};sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $relative));hash_mode='canonical-text-v1';lines=$lineCount;function_count=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count;parse_errors=0}
})
if($modules.Count-ne6-or(@($modules|Measure-Object function_count -Sum).Sum)-ne25){throw '[mir4-m42-02-pre-freeze-release-module-contract]'}
$facadeAst=Get-MIR4M4202PreFreezeReleaseAst $sourcePath;$facadeLines=@([IO.File]::ReadAllLines((Join-Path $repo $sourcePath))).Count
if(@($facadeAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count-ne0-or$facadeLines-gt20){throw '[mir4-m42-02-pre-freeze-release-facade]'}
$oldTokens=$null;$oldErrors=$null;$oldAst=[Management.Automation.Language.Parser]::ParseInput($sourceText,[ref]$oldTokens,[ref]$oldErrors)
$oldFunctions=@($oldAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object{$_.Name})
$currentFunctions=@(foreach($spec in $moduleSpecs){(Get-MIR4M4202PreFreezeReleaseAst "$moduleRoot/$($spec.name)").FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object{$_.Name}})
$oldProjectionSha=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $oldFunctions);$currentProjectionSha=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $currentFunctions)
if($oldFunctions.Count-ne25-or($oldFunctions-join'|')-cne($currentFunctions-join'|')-or$oldProjectionSha-cne$currentProjectionSha){throw '[mir4-m42-02-pre-freeze-release-public-contract]'}
$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
if([int]$inventory.command_count-ne85-or[int]$inventory.summary.unknown-ne0-or[int]$inventory.summary.duplicate_command_keys-ne0){throw '[mir4-m42-02-pre-freeze-release-inventory]'}
$evolvedPaths=@(
  '.mir/assurance.json','.mir/control/paths.yml','.mir/modules.yml','.mir/test-impact.yml','assurance/catalog/tests.json','docs/architecture/module-boundaries.md','governance/automation/mir4-command-inventory-v1.json',
  'tests/architecture/Test-MIRArchitecture.ps1','tests/mir4/Test-MIR4DocumentationCutoverM4105B.ps1','tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1','tests/repository/Test-MIR4RepositoryFixedPoint.ps1','tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1',
  'tests/tooling/Test-MIR4PowerShellCommandRouterDecompositionM4202.ps1','tests/tooling/Test-MIR4ValidationRunnerDecompositionM4202.ps1','tests/tooling/Test-MIR4AssuranceEvidenceDecompositionM4202.ps1',
  'tests/tooling/Test-MIRAssurance.ps1','tests/tooling/Test-MIRVerificationSchemas.ps1','tools/lib/mir4/PreFreezeRelease.ps1','tools/mir/application/repository/RepositoryFixedPoint.ps1','validation/tests.yml'
)
$evolvedBindings=@($evolvedPaths|ForEach-Object{[pscustomobject][ordered]@{path=$_;previous_sha256=(Get-MIR4M4202PreFreezeReleaseGitTextSha256 -Commit $startingCommit -RelativePath $_);current_sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $_));hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}})
$packageSourceSha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receipt=[pscustomobject][ordered]@{
  schema=1;kind='MIR4M4202PreFreezeReleaseDecompositionV1';status='M42-02-PS4-PRE-FREEZE-RELEASE-DECOMPOSED';starting_dev=[pscustomobject][ordered]@{commit=$startingCommit;tree=$startingTree}
  predecessor=[pscustomobject][ordered]@{work_package='M42-02-PS3-ASSURANCE-EVIDENCE';receipt=$predecessorPath;receipt_sha256=(Get-FileHash -LiteralPath (Join-Path $repo $predecessorPath) -Algorithm SHA256).Hash.ToUpperInvariant();record_sha256=[string]$predecessor.record_sha256;status=[string]$predecessor.status}
  characterization=[pscustomobject][ordered]@{receipt=$characterizationPath;record_sha256=[string]$characterization.record_sha256;path=$sourcePath;sha256=[string]$characterized[0].sha256;lines=[int]$characterized[0].lines;responsibilities=@($characterized[0].responsibilities)}
  current_source=[pscustomobject][ordered]@{commit=$startingCommit;tree=$startingTree;path=$sourcePath;sha256=$sourceSha256;lines=2283;function_count=25;evolution_chain=@('M42-02-PS1','M42-02-PS2','M42-02-PS3')}
  decomposition=[pscustomobject][ordered]@{responsibility='pre-freeze-release';facade=[pscustomobject][ordered]@{path=$sourcePath;previous_sha256=$sourceSha256;current_sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $sourcePath));hash_mode='canonical-text-v1';previous_lines=2283;current_lines=$facadeLines;maximum_lines=20;function_count=0};module_root=$moduleRoot;module_count=$modules.Count;module_maximum_lines=1000;modules=$modules;segment_algorithm='exact-current-function-source-slices-with-declared-ps4-successor-v1'}
  public_contract=[pscustomobject][ordered]@{projection_algorithm='ordered-powershell-function-name-list-v1';previous_sha256=$oldProjectionSha;current_sha256=$currentProjectionSha;unchanged=$true;function_count=$currentFunctions.Count}
  semantic_contract=[pscustomobject][ordered]@{source_segments_exact_except_declared_self_successor=$true;declared_self_successor_extension=$true;function_names_and_order_unchanged=$true;module_load_order_explicit=$true;authority_locks_unchanged=$true;pre_freeze_state_unchanged=$true;authority_chain_validation_unchanged_except_self_successor=$true;release_doctor_unchanged=$true;workflow_maturity_unchanged=$true;playtest_sessions_unchanged=$true}
  tooling_inventory=[pscustomobject][ordered]@{path='governance/automation/mir4-command-inventory-v1.json';sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo 'governance/automation/mir4-command-inventory-v1.json'));hash_mode='canonical-text-v1';digest=[string]$inventory.digest;command_count=[int]$inventory.command_count;unknown=[int]$inventory.summary.unknown;duplicate_command_keys=[int]$inventory.summary.duplicate_command_keys}
  evolved_bindings=$evolvedBindings;preservation=[pscustomobject][ordered]@{package_source_sha256=$packageSourceSha256;package_visible_delta=@();gameplay=$false;saves=$true;settings=$true;migrations=$true;compatibility_claims=$true}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false};next_fixed_point='M42-02-PS5-BOOTSTRAP-MATERIALIZATION';record_sha256=''
}
$receipt.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $receipt;$json=ConvertTo-MIR4M4202PreFreezeReleaseJson $receipt
if(-not($json|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-pre-freeze-release-decomposition-v1.schema.json'))){throw '[mir4-m42-02-pre-freeze-release-receipt-schema]'}
Set-MIR4M4202PreFreezeReleaseProjection -RelativePath 'releases/migrations/MIR4-M42-02-Pre-Freeze-Release-DecompositionV1.json' -Text $json
$receipt
