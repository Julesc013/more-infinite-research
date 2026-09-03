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

function Get-MIR4M4202PowerShellRawSha256([string]$RelativePath){
  $path=Join-Path $repo $RelativePath
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[mir4-m42-02-powershell-source] $RelativePath"}
  (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function ConvertTo-MIR4M4202PowerShellJson($Record){
  (($Record|ConvertTo-Json -Depth 100).Replace(([string][char]13+[char]10),[string][char]10)+[string][char]10)
}

function Set-MIR4M4202PowerShellProjection([string]$RelativePath,[string]$Json){
  $path=Join-Path $repo $RelativePath
  if($Check){
    $actual=if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::ReadAllText($path).Replace(([string][char]13+[char]10),[string][char]10)}else{''}
    if($actual-cne$Json){throw "[mir4-m42-02-powershell-stale] $RelativePath"}
    return
  }
  [IO.File]::WriteAllText($path,$Json,[Text.UTF8Encoding]::new($false))
}

$specs=@(
  [pscustomobject]@{path='tools/mir/cli/Invoke-MIRCommandRouter.ps1';decision='decompose';sequence=1;node='M42-02-PS1-COMMAND-ROUTER';responsibilities=@('argument parsing','command lookup','application invocation','result rendering');rationale='The sole public command router must remain a thin facade with bounded routing responsibilities.'},
  [pscustomobject]@{path='scripts/Invoke-MIRValidation.ps1';decision='decompose';sequence=2;node='M42-02-PS2-VALIDATION-RUNNER';responsibilities=@('static selection','runtime scenario setup','runtime execution','log and report assertions','package smoke policy');rationale='The executable test authority currently mixes portable selection, runtime execution, and result evaluation.'},
  [pscustomobject]@{path='tools/lib/assurance/Evidence.ps1';decision='decompose';sequence=3;node='M42-02-PS3-ASSURANCE-EVIDENCE';responsibilities=@('fingerprints','producer trust','worker import','evidence decisions','attempt state','command execution','plans','gates');rationale='Evidence construction, trust, execution, and aggregation are independently reviewable assurance responsibilities.'},
  [pscustomobject]@{path='tools/lib/mir4/PreFreezeRelease.ps1';decision='decompose';sequence=4;node='M42-02-PS4-PRE-FREEZE-RELEASE';responsibilities=@('authority locks','pre-freeze state','release doctor','workflow maturity','playtest sessions');rationale='The private 4.1 candidate path requires separately reviewable pre-freeze, doctor, workflow, and playtest owners.'},
  [pscustomobject]@{path='tools/lib/mir4/BootstrapMaterialization.ps1';decision='decompose';sequence=5;node='M42-02-PS5-BOOTSTRAP-MATERIALIZATION';responsibilities=@('digests and records','safe paths','archive comparison','git source proof','capsule closure');rationale='Bootstrap identity, safe extraction, comparison, source proof, and capsule closure require bounded internal modules.'},
  [pscustomobject]@{path='tools/lib/assurance/Release.ps1';decision='decompose';sequence=6;node='M42-02-PS6-ASSURANCE-RELEASE';responsibilities=@('release planning','candidate authority','seal authority','seal verification','self-test');rationale='Release planning and sealing are production-sensitive, and the embedded self-test must move to executable test authority.'},
  [pscustomobject]@{path='tools/commands/compatibility/Invoke-MIRCompatAudit.ps1';decision='decompose';sequence=7;node='M42-02-PS7-COMPATIBILITY-AUDIT';responsibilities=@('configuration','input discovery','scenario execution','result collation');rationale='Compatibility audit configuration, discovery, execution, and collation are separable without changing claims.'},
  [pscustomobject]@{path='tools/mir/application/custody/OfflineCandidateCustody.ps1';decision='decompose';sequence=8;node='M42-02-PS8-OFFLINE-CUSTODY';responsibilities=@('custody admission','seal inputs','signature verification','qualification evidence','offline restore');rationale='Offline custody and restore must expose bounded admission, verification, evidence, and recovery responsibilities.'},
  [pscustomobject]@{path='tools/lib/mir4/ReleaseCapsule.ps1';decision='decompose';sequence=9;node='M42-02-PS9-RELEASE-CAPSULE';responsibilities=@('inventory','capsule construction','capsule verification','restore');rationale='Release capsule inventory, construction, verification, and restore are distinct supply-chain review boundaries.'},
  [pscustomobject]@{path='tools/lib/control/Executor.ps1';decision='decompose';sequence=10;node='M42-02-PS10-CONTROL-EXECUTOR';responsibilities=@('execution state','environment','runtime jobs','performance jobs','aggregate gates');rationale='The control executor combines state, environment, heterogeneous workers, and final gate aggregation.'},
  [pscustomobject]@{path='tools/lib/mir4/SupplyChain.ps1';decision='decompose';sequence=11;node='M42-02-PS11-SUPPLY-CHAIN';responsibilities=@('inventory','attestation','policy verification','custody projection');rationale='Supply-chain inventory, attestation, policy verification, and custody projections need bounded owners.'},
  [pscustomobject]@{path='tools/commands/release/New-MIR4BootstrapLocalCandidate.ps1';decision='retain-with-explicit-waiver';sequence=0;node=$null;responsibilities=@('single bootstrap candidate command');rationale='The command is a single fail-closed bootstrap transaction; splitting it before source freeze would widen rollback risk.'},
  [pscustomobject]@{path='tools/lib/mir4/PlatformPreview.ps1';decision='retain-with-explicit-waiver';sequence=0;node=$null;responsibilities=@('read-only platform preview composition');rationale='The file is a read-only preview composer with no package, mutation, release, or publication authority.'},
  [pscustomobject]@{path='scripts/Measure-MIRPerformanceRegression.ps1';decision='retain-with-explicit-waiver';sequence=0;node=$null;responsibilities=@('one performance regression measurement transaction');rationale='The script is an isolated measurement transaction whose process and report lifecycle must remain atomic.'},
  [pscustomobject]@{path='scripts/Export-MIRApprovedDelta.ps1';decision='retain-with-explicit-waiver';sequence=0;node=$null;responsibilities=@('one approved-delta export transaction');rationale='The exporter has one bounded output contract and no authority to approve or apply the delta it renders.'},
  [pscustomobject]@{path='tools/lib/mir4/ReleaseAdapters.ps1';decision='retain-with-explicit-waiver';sequence=0;node=$null;responsibilities=@('release adapter registry');rationale='The adapter registry is cohesive and already delegates phase behavior to the canonical release application engine.'},
  [pscustomobject]@{path='tools/lib/assurance/Core.ps1';decision='retain-with-explicit-waiver';sequence=0;node=$null;responsibilities=@('assurance foundational primitives');rationale='The core contains stable low-level assurance primitives and does not own worker execution or release transitions.'},
  [pscustomobject]@{path='tools/lib/control/Views.ps1';decision='retain-with-explicit-waiver';sequence=0;node=$null;responsibilities=@('deterministic control-plane views');rationale='The file is a cohesive read-only rendering boundary over canonical control-plane records.'},
  [pscustomobject]@{path='tools/commands/release/Invoke-MIR4BootstrapCapsule.ps1';decision='retain-with-explicit-waiver';sequence=0;node=$null;responsibilities=@('single bootstrap capsule command');rationale='The command is a thin transactional adapter over capsule libraries and must retain one fail-closed exit boundary.'},
  [pscustomobject]@{path='tools/commands/compatibility/Convert-MIRCompatAuditResults.ps1';decision='retain-with-explicit-waiver';sequence=0;node=$null;responsibilities=@('compatibility result conversion');rationale='The converter owns one deterministic result projection and cannot run scenarios or raise compatibility claims.'}
)

$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
$thresholdRows=@($inventory.implementation_files|Where-Object{[string]$_.classification-ceq'canonical-internal'-and[int]$_.lines-ge600}|Sort-Object path)
if($thresholdRows.Count-ne20){throw "[mir4-m42-02-powershell-threshold-count] $($thresholdRows.Count)"}
$specByPath=@{}
foreach($spec in $specs){if($specByPath.ContainsKey([string]$spec.path)){throw "[mir4-m42-02-powershell-duplicate-spec] $($spec.path)"};$specByPath[[string]$spec.path]=$spec}
if($specByPath.Count-ne$thresholdRows.Count-or@($thresholdRows|Where-Object{-not$specByPath.ContainsKey([string]$_.path)}).Count-ne0){throw '[mir4-m42-02-powershell-unclassified-threshold-file]'}

$tracked=@(
  foreach($inventoryRow in $thresholdRows){
    $spec=$specByPath[[string]$inventoryRow.path]
    $path=Join-Path $repo ([string]$inventoryRow.path)
    $tokens=$null;$parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    if(@($parseErrors).Count-ne0){throw "[mir4-m42-02-powershell-parse] $($inventoryRow.path)"}
    $rawSha=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if($rawSha-cne[string]$inventoryRow.sha256){throw "[mir4-m42-02-powershell-inventory-drift] $($inventoryRow.path)"}
    [pscustomobject][ordered]@{
      path=[string]$inventoryRow.path;classification='canonical-internal';sha256=(Get-MIR4BootstrapTextSha256 -Path $path);hash_mode='canonical-text-v1';lines=[int]$inventoryRow.lines
      function_count=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count
      parse_errors=0;threshold_band=if([int]$inventoryRow.lines-gt1000){'explicit-disposition-required'}else{'split-or-explicit-waiver'}
      decision=[string]$spec.decision;sequence=[int]$spec.sequence;next_node=$spec.node;responsibilities=@($spec.responsibilities);rationale=[string]$spec.rationale
    }
  }
)
if(@($tracked|Where-Object{[string]$_.decision-ceq'decompose'}).Count-ne11-or@($tracked|Where-Object{[string]$_.decision-ceq'retain-with-explicit-waiver'}).Count-ne9){throw '[mir4-m42-02-powershell-disposition-count]'}

$packageSource=Get-Content -Raw -LiteralPath (Join-Path $repo 'src/mod/package-source.json')|ConvertFrom-Json -Depth 100 -DateKind String
$canonicalOutputs=@($packageSource.bindings|ForEach-Object{[string]$_.output_path}|Where-Object{$_-match'^prototypes/(?:mir/.+|streams/.+)[.]lua$'}|Sort-Object -Unique)
$moduleAssignments=@(Get-Content -LiteralPath (Join-Path $repo '.mir/modules.yml')|ForEach-Object{if($_-match'^    - (prototypes/(?:mir/.+|streams/.+)[.]lua)$'){$Matches[1]}}|Sort-Object -Unique)
if($canonicalOutputs.Count-ne267-or$moduleAssignments.Count-ne267-or@($canonicalOutputs|Where-Object{$_-notin$moduleAssignments}).Count-ne0){throw '[mir4-m42-02-powershell-module-reconciliation]'}

$l6Path='releases/migrations/MIR4-M42-02-Compiler-Orchestrator-DecompositionV1.json'
$l6=Get-Content -Raw -LiteralPath (Join-Path $repo $l6Path)|ConvertFrom-Json -Depth 100 -DateKind String
$bindingPaths=@('.mir/assurance.json','.mir/control/paths.yml','.mir/modules.yml','.mir/test-impact.yml','assurance/catalog/tests.json','governance/automation/mir4-command-inventory-v1.json','tests/architecture/Test-MIRArchitecture.ps1','tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1','tests/repository/Test-MIR4RepositoryFixedPoint.ps1','tests/tooling/Test-MIR4TestWorkflowConvergence.ps1','validation/tests.yml','tools/lib/mir4/PreFreezeRelease.ps1')
$receipt=[pscustomobject][ordered]@{
  schema=1;kind='MIR4M4202PowerShellCharacterizationV1';status='M42-02-RESIDUAL-POWERSHELL-CHARACTERIZED'
  starting_dev=[pscustomobject][ordered]@{commit='337d60ffe6e9dd1c5493b17c4d4b278c16881e2d';tree='9ac1d4541ff82b6b2dac37e1a25fb4f7146a7e90'}
  predecessor=[pscustomobject][ordered]@{work_package='M42-02-L6';receipt=$l6Path;receipt_sha256=(Get-MIR4M4202PowerShellRawSha256 $l6Path);record_sha256=[string]$l6.record_sha256;status=[string]$l6.status}
  inventory=[pscustomobject][ordered]@{path='governance/automation/mir4-command-inventory-v1.json';sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo 'governance/automation/mir4-command-inventory-v1.json'));hash_mode='canonical-text-v1';digest=[string]$inventory.digest;canonical_internal=[int]$inventory.summary.canonical_internal;unknown=[int]$inventory.summary.unknown;reviewed_file_count=$tracked.Count}
  threshold_policy=[pscustomobject][ordered]@{normal_maximum_lines=400;review_maximum_lines=600;split_normally_maximum_lines=1000;explicit_disposition_minimum_lines=1001;decompose_count=11;waiver_count=9}
  tracked_files=$tracked
  decomposition_sequence=@($tracked|Where-Object{[string]$_.decision-ceq'decompose'}|Sort-Object sequence|ForEach-Object{[pscustomobject][ordered]@{sequence=[int]$_.sequence;node=[string]$_.next_node;path=[string]$_.path}})
  waivers=@($tracked|Where-Object{[string]$_.decision-ceq'retain-with-explicit-waiver'}|ForEach-Object{[string]$_.path}|Sort-Object)
  architecture_reconciliation=[pscustomobject][ordered]@{authority='src/mod/package-source.json#bindings[].output_path';canonical_output_count=$canonicalOutputs.Count;assigned_output_count=$moduleAssignments.Count;added_assignments=9;removed_stale_assignments=2;module_manifest_sha256=(Get-MIR4M4202PowerShellRawSha256 '.mir/modules.yml');architecture_test='tests/architecture/Test-MIRArchitecture.ps1'}
  authority_bindings=@($bindingPaths|ForEach-Object{[pscustomobject][ordered]@{path=$_;sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $_));hash_mode='canonical-text-v1';package_visible=$false}})
  preservation=[pscustomobject][ordered]@{package_source_sha256=(Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo);package_visible_delta=@();gameplay=$false;saves=$true;settings=$true;migrations=$true;compatibility_claims=$true}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  next_fixed_point='M42-02-PS1-COMMAND-ROUTER';record_sha256=''
}
$receipt.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $receipt
$json=ConvertTo-MIR4M4202PowerShellJson $receipt
if(-not($json|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-powershell-characterization-v1.schema.json'))){throw '[mir4-m42-02-powershell-receipt-schema]'}
Set-MIR4M4202PowerShellProjection -RelativePath 'releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json' -Json $json
$receipt
