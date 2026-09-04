[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Set-MIR4M4202SupplyChainProjection {
  param([string]$RelativePath, [string]$Text)
  $path = Join-Path $repo $RelativePath
  if ($Check) {
    $actual = if (Test-Path -LiteralPath $path -PathType Leaf) { [IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n") } else { '' }
    if ($actual -cne $Text) { throw "[mir4-m42-02-supply-chain-stale] $RelativePath" }
    return
  }
  $parent = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Path $parent) }
  [IO.File]::WriteAllText($path, $Text, [Text.UTF8Encoding]::new($false))
}

function Get-MIR4M4202SupplyChainGitText {
  param([string]$Commit, [string]$RelativePath)
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = 'git'; $start.UseShellExecute = $false; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
  foreach ($argument in @('-C', $repo, 'show', ($Commit + ':' + $RelativePath))) { [void]$start.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::Start($start)
  $text = $process.StandardOutput.ReadToEnd(); $errorText = $process.StandardError.ReadToEnd(); $process.WaitForExit()
  if ($process.ExitCode -ne 0) { throw "[mir4-m42-02-supply-chain-git-source] $Commit|$RelativePath|$errorText" }
  $text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-MIR4M4202SupplyChainSlice {
  param([string[]]$Lines, [int]$Start, [int]$End)
  (@($Lines[($Start - 1)..($End - 1)]) -join [char]10) + [char]10
}

function Get-MIR4M4202SupplyChainAst {
  param([string]$RelativePath)
  $tokens = $null; $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $RelativePath), [ref]$tokens, [ref]$errors)
  if (@($errors).Count -ne 0) { throw "[mir4-m42-02-supply-chain-parse] $RelativePath" }
  $ast
}

function Get-MIR4M4202SupplyChainGitTextSha256 {
  param([string]$Commit, [string]$RelativePath)
  Get-MIR4Sha256String -Value (Get-MIR4M4202SupplyChainGitText -Commit $Commit -RelativePath $RelativePath)
}

$startingCommit = 'c478122e29160ceea12e7d931f1f8ce68b020134'
$startingTree = 'bf189044b12ccda2de562cdeeaea576ee483524e'
$sourcePath = 'tools/lib/mir4/SupplyChain.ps1'
$sourceSha256 = '3D1CAF10F2EA14B21743BA3E8B1018930695816B7181D26A8B704B63152DC1D4'
$sourceText = Get-MIR4M4202SupplyChainGitText -Commit $startingCommit -RelativePath $sourcePath
$sourceLines = @($sourceText.Split([char]10))
if (-not $sourceText.EndsWith([string][char]10) -or (Get-MIR4Sha256String -Value $sourceText) -cne $sourceSha256 -or $sourceLines.Count -ne 1104) { throw '[mir4-m42-02-supply-chain-starting-source]' }

$moduleRoot = 'tools/lib/mir4/supply-chain'
$moduleSpecs = @(
  [pscustomobject]@{name='CoreAndRows.ps1';role='authority, source identity, file rows, and repository tree custody projection';start=12;end=208},
  [pscustomobject]@{name='ArchiveAndSelection.ps1';role='canonical archive rows, row selection, package rows, and identity sets';start=209;end=398},
  [pscustomobject]@{name='ComponentInventory.ps1';role='component inventory construction and verification';start=399;end=569},
  [pscustomobject]@{name='SpdxAttestation.ps1';role='SPDX 3.0.1 and 2.3 attestation construction';start=570;end=817},
  [pscustomobject]@{name='ProvenanceAndVerification.ps1';role='SLSA provenance, policy verification, compatibility verification, and record writing';start=818;end=1103}
)

$expectedModules = @{}
foreach ($spec in $moduleSpecs) {
  $relative = "$moduleRoot/$($spec.name)"
  $text = Get-MIR4M4202SupplyChainSlice -Lines $sourceLines -Start $spec.start -End $spec.end
  $expectedModules[$relative] = $text
  Set-MIR4M4202SupplyChainProjection -RelativePath $relative -Text $text
}
$setupBlock = Get-MIR4M4202SupplyChainSlice -Lines $sourceLines -Start 1 -End 11
$facadeTail = @'
. (Join-Path $PSScriptRoot 'supply-chain/CoreAndRows.ps1')
. (Join-Path $PSScriptRoot 'supply-chain/ArchiveAndSelection.ps1')
. (Join-Path $PSScriptRoot 'supply-chain/ComponentInventory.ps1')
. (Join-Path $PSScriptRoot 'supply-chain/SpdxAttestation.ps1')
. (Join-Path $PSScriptRoot 'supply-chain/ProvenanceAndVerification.ps1')
'@.Replace("`r`n", "`n")
$facade = $setupBlock + $facadeTail
Set-MIR4M4202SupplyChainProjection -RelativePath $sourcePath -Text $facade

$predecessorPath = 'releases/migrations/MIR4-M42-02-Control-Executor-DecompositionV1.json'
$predecessor = Get-Content -Raw -LiteralPath (Join-Path $repo $predecessorPath) | ConvertFrom-Json -Depth 100 -DateKind String
if ([string]$predecessor.status -cne 'M42-02-PS10-CONTROL-EXECUTOR-DECOMPOSED' -or [string]$predecessor.next_fixed_point -cne 'M42-02-PS11-SUPPLY-CHAIN' -or -not (Test-MIR4BootstrapRecordHash -Record $predecessor)) { throw '[mir4-m42-02-supply-chain-predecessor]' }
$characterizationPath = 'releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
$characterization = Get-Content -Raw -LiteralPath (Join-Path $repo $characterizationPath) | ConvertFrom-Json -Depth 100 -DateKind String
$characterized = @($characterization.tracked_files | Where-Object { [string]$_.path -ceq $sourcePath })
if ($characterized.Count -ne 1 -or [string]$characterized[0].sha256 -cne $sourceSha256 -or [int]$characterized[0].sequence -ne 11 -or [string]$characterized[0].next_node -cne 'M42-02-PS11-SUPPLY-CHAIN') { throw '[mir4-m42-02-supply-chain-characterization]' }

$modules = @(
  foreach ($spec in $moduleSpecs) {
    $relative = "$moduleRoot/$($spec.name)"; $actual = [IO.File]::ReadAllText((Join-Path $repo $relative)).Replace("`r`n", "`n").Replace("`r", "`n")
    if ($actual -cne [string]$expectedModules[$relative]) { throw "[mir4-m42-02-supply-chain-segment] $relative" }
    $ast = Get-MIR4M4202SupplyChainAst -RelativePath $relative; $lineCount = @([IO.File]::ReadAllLines((Join-Path $repo $relative))).Count
    if ($lineCount -gt 400) { throw "[mir4-m42-02-supply-chain-module-lines] $relative|$lineCount" }
    [pscustomobject][ordered]@{path=$relative;role=[string]$spec.role;source_start_line=[int]$spec.start;source_end_line=[int]$spec.end;lines=$lineCount;sha256=Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $relative);hash_mode='canonical-text-v1';function_count=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)).Count}
  }
)
$facadeAst = Get-MIR4M4202SupplyChainAst -RelativePath $sourcePath; $facadeLines = @([IO.File]::ReadAllLines((Join-Path $repo $sourcePath))).Count
if ($facadeLines -gt 80 -or @($facadeAst.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)).Count -ne 0) { throw '[mir4-m42-02-supply-chain-facade]' }
$oldTokens=$null;$oldErrors=$null;$oldAst=[Management.Automation.Language.Parser]::ParseInput($sourceText,[ref]$oldTokens,[ref]$oldErrors)
$oldFunctions=@($oldAst.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object{$_.Name})
$currentFunctions=@(foreach($spec in $moduleSpecs){(Get-MIR4M4202SupplyChainAst -RelativePath "$moduleRoot/$($spec.name)").FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object{$_.Name}})
if (@($oldErrors).Count -ne 0 -or $oldFunctions.Count -ne 28 -or ($oldFunctions -join '|') -cne ($currentFunctions -join '|')) { throw '[mir4-m42-02-supply-chain-public-contract]' }

$inventory = if($Check){Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check}else{Update-MIR4CommandInventoryV1 -RepoRoot $repo}
if([int]$inventory.command_count-ne85-or[int]$inventory.summary.unknown-ne0-or[int]$inventory.summary.duplicate_command_keys-ne0){throw '[mir4-m42-02-supply-chain-inventory]'}
$evolvedPaths = @(
  '.mir/assurance.json','.mir/control/paths.yml','.mir/modules.yml','.mir/test-impact.yml','assurance/catalog/tests.json',
  'docs/architecture/module-boundaries.md','docs/releases/mir4-post-4.0-roadmap.md','governance/automation/mir4-command-inventory-v1.json','mir.lock',
  'sdk/preview/mir4/reference/compilation-runs.json','sdk/preview/mir4/reference/inspection-bundle-v1.json','sdk/preview/mir4/reference/inspector-workbench-result-v1.json','sdk/preview/mir4/reference/query-snapshot-f210.json',
  'spec/programmes/mir4-4x-operating-programme-v1.json','todo.md','tests/architecture/Test-MIRArchitecture.ps1','tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1','tests/mir4/Test-MIR4SupplyChainFoundation.ps1','tests/mir4/Test-MIR4SupplyChainAttestation.ps1','tests/mir4/Test-MIR4SupplyChainPreservationT15.ps1','tests/repository/Test-MIR4RepositoryFixedPoint.ps1',
  'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1','tests/tooling/Test-MIR4PowerShellCommandRouterDecompositionM4202.ps1','tests/tooling/Test-MIR4ValidationRunnerDecompositionM4202.ps1','tests/tooling/Test-MIR4AssuranceEvidenceDecompositionM4202.ps1','tests/tooling/Test-MIR4PreFreezeReleaseDecompositionM4202.ps1','tests/tooling/Test-MIR4BootstrapMaterializationDecompositionM4202.ps1','tests/tooling/Test-MIR4AssuranceReleaseDecompositionM4202.ps1','tests/tooling/Test-MIR4CompatibilityAuditDecompositionM4202.ps1','tests/tooling/Test-MIR4OfflineCustodyDecompositionM4202.ps1','tests/tooling/Test-MIR4ReleaseCapsuleDecompositionM4202.ps1','tests/tooling/Test-MIR4ControlExecutorDecompositionM4202.ps1',
  'tools/lib/mir4/SupplyChain.ps1','tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1','validation/tests.yml'
)
$evolvedBindings=@($evolvedPaths|ForEach-Object{[pscustomobject][ordered]@{path=$_;previous_sha256=Get-MIR4M4202SupplyChainGitTextSha256 -Commit $startingCommit -RelativePath $_;current_sha256=Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $_);hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}})
$receipt=[pscustomobject][ordered]@{
  schema=1;kind='MIR4M4202SupplyChainDecompositionV1';status='M42-02-PS11-SUPPLY-CHAIN-DECOMPOSED-POWERSHELL-SEQUENCE-COMPLETE';starting_dev=[pscustomobject][ordered]@{commit=$startingCommit;tree=$startingTree}
  predecessor=[pscustomobject][ordered]@{work_package='M42-02-PS10-CONTROL-EXECUTOR';receipt=$predecessorPath;receipt_sha256=(Get-FileHash -LiteralPath (Join-Path $repo $predecessorPath) -Algorithm SHA256).Hash.ToUpperInvariant();record_sha256=[string]$predecessor.record_sha256;status=[string]$predecessor.status}
  characterization=[pscustomobject][ordered]@{receipt=$characterizationPath;record_sha256=[string]$characterization.record_sha256;path=$sourcePath;sha256=$sourceSha256;lines=[int]$characterized[0].lines;responsibilities=@($characterized[0].responsibilities)}
  current_source=[pscustomobject][ordered]@{commit=$startingCommit;tree=$startingTree;path=$sourcePath;sha256=$sourceSha256;lines=1104;function_count=28;evolution_chain=@()}
  decomposition=[pscustomobject][ordered]@{responsibility='supply-chain';facade=[pscustomobject][ordered]@{path=$sourcePath;previous_sha256=$sourceSha256;current_sha256=Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $sourcePath);hash_mode='canonical-text-v1';previous_lines=1104;current_lines=$facadeLines;maximum_lines=80;function_count=0};module_root=$moduleRoot;module_count=$modules.Count;module_maximum_lines=400;modules=$modules;segment_algorithm='ordered-current-source-slices-v1'}
  public_contract=[pscustomobject][ordered]@{function_projection_algorithm='ordered-powershell-function-name-list-v1';previous_function_sha256=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $oldFunctions);current_function_sha256=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $currentFunctions);setup_block_sha256=Get-MIR4Sha256String -Value $setupBlock;unchanged=$true;function_count=$currentFunctions.Count}
  semantic_contract=[pscustomobject][ordered]@{ordered_current_source_slices_preserved=$true;function_names_and_order_unchanged=$true;setup_unchanged=$true;module_load_order_explicit=$true;inventory_and_source_identity_unchanged=$true;archive_and_selection_unchanged=$true;component_inventory_unchanged=$true;spdx_attestation_unchanged=$true;slsa_provenance_unchanged=$true;policy_verification_unchanged=$true;custody_record_writing_unchanged=$true;platform_projections_regenerated=$true;pre_freeze_authority_chain_extended_for_ps11=$true;powershell_decomposition_sequence_complete=$true}
  programme_transition=[pscustomobject][ordered]@{work_package='M42-02';previous_state='active';current_state='complete';next_programme='M43-00';next_programme_state='queued';mir41_qualification_still_required=$true}
  tooling_inventory=[pscustomobject][ordered]@{path='governance/automation/mir4-command-inventory-v1.json';sha256=Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo 'governance/automation/mir4-command-inventory-v1.json');hash_mode='canonical-text-v1';digest=[string]$inventory.digest;command_count=[int]$inventory.command_count;unknown=[int]$inventory.summary.unknown;duplicate_command_keys=[int]$inventory.summary.duplicate_command_keys}
  evolved_bindings=$evolvedBindings
  preservation=[pscustomobject][ordered]@{package_source_sha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo;package_visible_delta=@();gameplay=$false;saves=$true;settings=$true;migrations=$true;compatibility_claims=$true;stream_identities=$true}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  next_fixed_point='M41-BRIDGE-RETIREMENT';record_sha256=''
}
$receipt.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $receipt
$json=($receipt|ConvertTo-Json -Depth 100).Replace("`r`n","`n")+[char]10
if(-not($json|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-supply-chain-decomposition-v1.schema.json'))){throw '[mir4-m42-02-supply-chain-receipt-schema]'}
Set-MIR4M4202SupplyChainProjection -RelativePath 'releases/migrations/MIR4-M42-02-Supply-Chain-DecompositionV1.json' -Text $json
$receipt
