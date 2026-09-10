# MIR4-CANONICAL-EXECUTABLE-TEST
# Append-only materializer for bounded A05 K2-02/04/05/06/07 qualification.
param(
  [string]$RepoRoot='',
  [string]$RuntimeResult='build/mir4/a05-k2-materials/k2-materials-runtime-reviewed-forward-rerun/result.json',
  [switch]$RequireLocalEvidence
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if(-not $RequireLocalEvidence){throw '[mir4-a05-k2-materials-local-evidence-required]'}
if(-not $RepoRoot){$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-A05K2Closure { param([bool]$Condition,[string]$Code) if(-not $Condition){throw $Code} }
function Resolve-A05K2ClosurePath { param([string]$Relative,[bool]$Required=$true)
  Assert-A05K2Closure ($Relative -cmatch '^[A-Za-z0-9._/-]+$' -and $Relative -notmatch '(^|/)\.\.(/|$)') "[mir4-a05-k2-materials-relative] $Relative"
  $path=[IO.Path]::GetFullPath((Join-Path $RepoRoot $Relative))
  $prefix=$RepoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  Assert-A05K2Closure ($path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) "[mir4-a05-k2-materials-escape] $Relative"
  if($Required){Assert-A05K2Closure (Test-Path -LiteralPath $path -PathType Leaf) "[mir4-a05-k2-materials-missing] $Relative"}
  $path
}
function Get-A05K2ClosureArtifact { param([string]$Relative)
  $path=Resolve-A05K2ClosurePath $Relative $true
  $item=Get-Item -LiteralPath $path
  [pscustomobject][ordered]@{path=$Relative;bytes=[long]$item.Length;raw_sha256=Get-MIR4Sha256File -Path $path}
}
function Assert-A05K2ClosureArtifact { param($Artifact,[string]$Code)
  Assert-A05K2Closure ($null -ne $Artifact -and [string]$Artifact.path -cmatch '^[A-Za-z0-9._/-]+$' -and [long]$Artifact.bytes -ge 0 -and [string]$Artifact.raw_sha256 -cmatch '^[A-F0-9]{64}$') $Code
  $actual=Get-A05K2ClosureArtifact ([string]$Artifact.path)
  Assert-A05K2Closure ($actual.bytes -eq [long]$Artifact.bytes -and $actual.raw_sha256 -ceq [string]$Artifact.raw_sha256) "$Code-local"
  $actual
}
function Get-A05K2ClosureAbsoluteArtifact { param([string]$Path,[string]$ExpectedSha,[string]$Code)
  $full=[IO.Path]::GetFullPath($Path)
  $prefix=$RepoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  Assert-A05K2Closure ($full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) '[mir4-a05-k2-materials-private-artifact]'
  $relative=$full.Substring($prefix.Length).Replace('\','/')
  $actual=Get-A05K2ClosureArtifact $relative
  Assert-A05K2Closure ($actual.raw_sha256 -ceq $ExpectedSha) $Code
  $actual
}
function Get-A05K2ClosureSource { param([string]$Relative)
  [pscustomobject][ordered]@{path=$Relative;canonical_sha256=Get-MIR4BootstrapTextSha256 -Path (Resolve-A05K2ClosurePath $Relative $true)}
}
function Get-A05K2ClosureRecordBinding { param([string]$Relative)
  $path=Resolve-A05K2ClosurePath $Relative $true
  $record=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-A05K2Closure (Test-MIR4BootstrapRecordHash $record) "[mir4-a05-k2-materials-record-lineage] $Relative"
  [pscustomobject][ordered]@{path=$Relative;raw_sha256=Get-MIR4Sha256File -Path $path;record_sha256=[string]$record.record_sha256}
}
function Write-A05K2ClosureRecord { param($Record,[string]$Relative)
  $target=Resolve-A05K2ClosurePath $Relative $false
  $scratch=Join-Path $RepoRoot 'build/a05-k2-materials/closure-record.scratch'
  [IO.Directory]::CreateDirectory((Split-Path -Parent $scratch))|Out-Null
  Write-MIR4BootstrapRecord -Record $Record -Path $scratch|Out-Null
  $text=[IO.File]::ReadAllText($scratch)
  Assert-A05K2Closure ($text|Test-Json -SchemaFile (Resolve-A05K2ClosurePath 'spec/schemas/mir4-a05-k2-materials-closure-v1.schema.json' $true)) '[mir4-a05-k2-materials-schema]'
  Assert-A05K2Closure ($text-notmatch '(?i)(?:[A-Z]:[\\/]|\\\\)') '[mir4-a05-k2-materials-private-record]'
  if(Test-Path -LiteralPath $target){Assert-A05K2Closure ([IO.File]::ReadAllText($target)-ceq$text) '[mir4-a05-k2-materials-immutable-overwrite]'}else{[IO.Directory]::CreateDirectory((Split-Path -Parent $target))|Out-Null;[IO.File]::Move($scratch,$target)}
  [pscustomobject][ordered]@{path=$Relative;raw_sha256=Get-MIR4Sha256File -Path $target;record_sha256=(Get-Content -Raw -LiteralPath $target|ConvertFrom-Json -Depth 100 -DateKind String).record_sha256}
}
function Write-A05K2EvolutionRecord { param($Record,[string]$Relative)
  $target=Resolve-A05K2ClosurePath $Relative $false
  $scratch=Join-Path $RepoRoot 'build/a05-k2-materials/evolution-record.scratch'
  [IO.Directory]::CreateDirectory((Split-Path -Parent $scratch))|Out-Null
  Write-MIR4BootstrapRecord -Record $Record -Path $scratch|Out-Null
  $text=[IO.File]::ReadAllText($scratch)
  Assert-A05K2Closure ($text|Test-Json -SchemaFile (Resolve-A05K2ClosurePath 'spec/schemas/mir4-a05-k2-materials-command-inventory-evolution-v1.schema.json' $true)) '[mir4-a05-k2-materials-evolution-schema]'
  Assert-A05K2Closure ($text-notmatch '(?i)(?:[A-Z]:[\\/]|\\\\)') '[mir4-a05-k2-materials-evolution-private-record]'
  if(Test-Path -LiteralPath $target){Assert-A05K2Closure ([IO.File]::ReadAllText($target)-ceq$text) '[mir4-a05-k2-materials-evolution-immutable-overwrite]'}else{[IO.Directory]::CreateDirectory((Split-Path -Parent $target))|Out-Null;[IO.File]::Move($scratch,$target)}
  Get-A05K2ClosureRecordBinding $Relative
}
function Assert-A05K2ProfileArchives { param($Case,[string]$Version,[bool]$ExpectXy)
  $required=@('flib_0.17.2.zip','k2so-assets_1.0.7.zip','Krastorio2_2.1.2.zip',"Krastorio2-spaced-out_$Version.zip",'Krastorio2Assets_2.1.0.zip','Krastorio2MenuSimulations_2.1.0.zip','mir-validation-settings-overrides_0.1.0.zip')
  if($ExpectXy){$required+='xy-k2so-enhancements-nulls-fork_0.8.3.zip'}
  $actual=@($Case.mod_archives|ForEach-Object{Split-Path -Leaf ([string]$_.path)}|Sort-Object)
  Assert-A05K2Closure ((@($actual)-join'|')-ceq(@($required|Sort-Object)-join'|')) "[mir4-a05-k2-materials-profile-archives] $Version"
  foreach($artifact in @($Case.mod_archives)){ $null=Assert-A05K2ClosureArtifact $artifact "[mir4-a05-k2-materials-mod-archive] $Version" }
  $xy=@($Case.mod_archives|Where-Object{[string]$_.path -match 'xy-k2so-enhancements-nulls-fork'})
  Assert-A05K2Closure (($ExpectXy -and $xy.Count-eq1 -and $xy[0].raw_sha256 -ceq '930F43B96B04012FEF090C40D8B16A6B3F259D1713C86CF59DFF3E9A5A97E2BE') -or ((-not $ExpectXy) -and $xy.Count-eq0)) "[mir4-a05-k2-materials-xy-profile] $Version"
}
function Get-A05K2PavingRoutes { param($Fresh,[string]$Version)
  $logPath=Resolve-A05K2ClosurePath ([string]$Fresh.factorio_log.path) $true
  $matches=@([regex]::Matches([IO.File]::ReadAllText($logPath),'(?m)^.*\[MIR4_A05_K2_MATERIAL_PAVING_ROUTES\] (.+)$'))
  Assert-A05K2Closure ($matches.Count-eq1) "[mir4-a05-k2-materials-paving-marker] $Version"
  $routes=@($matches[0].Groups[1].Value.Split(',')|Where-Object{$_})
  Assert-A05K2Closure ($routes.Count-gt0 -and @($routes|Where-Object{$_-notmatch'^[^|]+\|class=(?:manufacturing|recolor-return|recycling|crushing)\|permission=(?:nil|false)\|owner=\|in=[^|]*\|out=[^|]*$'}).Count-eq0) "[mir4-a05-k2-materials-paving-shape] $Version"
  Assert-A05K2Closure ((@($routes)-join'|')-ceq(@($routes|Sort-Object)-join'|')) "[mir4-a05-k2-materials-paving-sort] $Version"
  $routes
}
function Assert-A05K2FreshMarkers { param($Fresh,[string]$Version)
  $logPath=Resolve-A05K2ClosurePath ([string]$Fresh.factorio_log.path) $true
  $markers=@('[MIR4_A05_K2_MATERIAL_TECH] name=recipe-prod-research_material_rare_metals-1;effects=kr-rare-metals-from-enriched-rare-metals=0.02,kr-rare-metals=0.02;science=automation-science-pack,chemical-science-pack,logistic-science-pack;labs=biolab,kr-advanced-lab,kr-singularity-lab,lab','[MIR4_A05_K2_MATERIAL_TECH] name=recipe-prod-research_material_silicon-1;effects=kr-silicon=0.02;science=automation-science-pack,logistic-science-pack;labs=biolab,kr-advanced-lab,kr-singularity-lab,lab','[MIR4_A05_K2_MATERIAL_TECH] name=recipe-prod-research_material_glass-1;effects=kr-glass=0.02;science=automation-science-pack,chemical-science-pack,logistic-science-pack;labs=biolab,kr-advanced-lab,kr-singularity-lab,lab','[MIR4_A05_K2_MATERIAL_ROUTE] rare=ore:2>rare:1;enriched:1>rare:1;silicon=quartz:18>silicon:9;glass=sand:16>glass:8;casting=dirty-water:ignored_by_productivity:5;black_paving=withheld-final-denial;white_paving=withheld-final-denial','Material route omitted recipe=kr-casting-rare-metals reason=potential-return-path:water')
  foreach($marker in $markers){Assert-A05K2Closure (@(Select-String -LiteralPath $logPath -SimpleMatch $marker).Count-eq1) "[mir4-a05-k2-materials-fresh-marker] $Version"}
}
function Convert-A05K2Case { param($Case,[string]$Version,[bool]$ExpectXy)
  $expectedId=if($Version-eq'2.0.13'){'locked-2.0.13'}else{'current-2.0.17'}
  $expectedArchive=if($Version-eq'2.0.13'){'A2EEB2E5A6119C4117BD3653979D40D305D17539E184BFA6F4ED53EF12A5F242'}else{'0D48E22858FB4D1259413B65FFA7E5A0C5B5C2439A4918D58BDACC9411FA9284'}
  Assert-A05K2Closure ($Case.id-eq$expectedId -and $Case.k2so.version-eq$Version -and $Case.k2so.archive_sha256-eq$expectedArchive -and [bool]$Case.xy_enabled-eq$ExpectXy -and $Case.fresh_load.passed -and $Case.reloads.passed -and [int]$Case.reloads.required_count-eq2 -and [int]$Case.reloads.actual_count-eq2) "[mir4-a05-k2-materials-case] $Version"
  Assert-A05K2ProfileArchives $Case $Version $ExpectXy
  $fresh=[pscustomobject][ordered]@{save=Assert-A05K2ClosureArtifact $Case.fresh_load.save "[mir4-a05-k2-materials-fresh-save] $Version";stdout=Assert-A05K2ClosureArtifact $Case.fresh_load.stdout "[mir4-a05-k2-materials-fresh-stdout] $Version";stderr=Assert-A05K2ClosureArtifact $Case.fresh_load.stderr "[mir4-a05-k2-materials-fresh-stderr] $Version";factorio_log=Assert-A05K2ClosureArtifact $Case.fresh_load.factorio_log "[mir4-a05-k2-materials-fresh-log] $Version"}
  Assert-A05K2FreshMarkers $fresh $Version
  $pavingRoutes=Get-A05K2PavingRoutes $fresh $Version
  Assert-A05K2Closure ((@($Case.paving_routes)-join'|')-ceq(@($pavingRoutes)-join'|')) "[mir4-a05-k2-materials-paving-runtime-binding] $Version"
  $reloads=@()
  foreach($reload in @($Case.reloads.reloads|Sort-Object ordinal)){
    Assert-A05K2Closure ($reload.passed -and $reload.exit_code-eq0 -and -not$reload.timed_out -and $reload.save_byte_identical -and $reload.reload_log_contract_passed -and $reload.input_save_sha256-eq$fresh.save.raw_sha256 -and $reload.save_sha256-eq$fresh.save.raw_sha256) "[mir4-a05-k2-materials-reload] $Version/$($reload.ordinal)"
    $log=Get-A05K2ClosureAbsoluteArtifact $reload.factorio_log $reload.factorio_log_sha256 "[mir4-a05-k2-materials-reload-log] $Version/$($reload.ordinal)"
    foreach($marker in @($Case.reloads.required_log_fragments)){Assert-A05K2Closure (@(Select-String -LiteralPath (Resolve-A05K2ClosurePath $log.path $true) -SimpleMatch $marker).Count-eq1) "[mir4-a05-k2-materials-marker] $Version/$($reload.ordinal)"}
    $reloads+=[pscustomobject][ordered]@{ordinal=[int]$reload.ordinal;input_save_sha256=$reload.input_save_sha256;save_sha256=$reload.save_sha256;stdout=Get-A05K2ClosureAbsoluteArtifact $reload.stdout $reload.stdout_sha256 "[mir4-a05-k2-materials-reload-stdout] $Version/$($reload.ordinal)";stderr=Get-A05K2ClosureAbsoluteArtifact $reload.stderr $reload.stderr_sha256 "[mir4-a05-k2-materials-reload-stderr] $Version/$($reload.ordinal)";factorio_log=$log}
  }
  Assert-A05K2Closure ($reloads.Count-eq2) "[mir4-a05-k2-materials-reload-count] $Version"
  [pscustomobject][ordered]@{k2so_version=$Version;k2so_archive_sha256=$expectedArchive;xy_enabled=$ExpectXy;paving_routes=$pavingRoutes;fresh_load=$fresh;mod_archives=@($Case.mod_archives|ForEach-Object{Assert-A05K2ClosureArtifact $_ "[mir4-a05-k2-materials-mod-archive-record] $Version"});fixture=Assert-A05K2ClosureArtifact $Case.fixture "[mir4-a05-k2-materials-fixture] $Version";candidate=Assert-A05K2ClosureArtifact $Case.candidate "[mir4-a05-k2-materials-case-candidate] $Version";mod_list=Assert-A05K2ClosureArtifact $Case.mod_list "[mir4-a05-k2-materials-mod-list] $Version";mod_settings=Assert-A05K2ClosureArtifact $Case.mod_settings "[mir4-a05-k2-materials-mod-settings] $Version";reloads=$reloads}
}

$runtimeRelative=$RuntimeResult.Replace('\','/')
$runtime=Get-Content -Raw -LiteralPath (Resolve-A05K2ClosurePath $runtimeRelative $true)|ConvertFrom-Json -Depth 100 -DateKind String
Assert-A05K2Closure (-not[string]::IsNullOrWhiteSpace([string]$runtime.generated_at)) '[mir4-a05-k2-materials-runtime-timestamp]'
Assert-A05K2Closure ($runtime.kind-eq'MIR4A05K2MaterialsRuntimeResultV1' -and $runtime.engine.version-eq'2.1.17' -and $runtime.engine.executable_sha256-eq'710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8') '[mir4-a05-k2-materials-runtime-contract]'
$candidate=Assert-A05K2ClosureArtifact $runtime.candidate '[mir4-a05-k2-materials-candidate]'
Assert-A05K2Closure ($candidate.raw_sha256-eq'A6D5D264BE0153310BBE1E61ACDAAFE6407AA4D654B13B5251E680A0D3CADDF8') '[mir4-a05-k2-materials-candidate-lock]'
foreach($artifact in @($runtime.fixture)){ $null=Assert-A05K2ClosureArtifact $artifact '[mir4-a05-k2-materials-fixture-source]' }
$locked=Convert-A05K2Case $runtime.locked '2.0.13' $true
$current=Convert-A05K2Case $runtime.current '2.0.17' $false
Assert-A05K2Closure ($locked.candidate.raw_sha256-eq$candidate.raw_sha256 -and $current.candidate.raw_sha256-eq$candidate.raw_sha256) '[mir4-a05-k2-materials-candidate-parity]'
Assert-A05K2Closure ((@($locked.paving_routes)-join'|')-ceq(@($current.paving_routes)-join'|')) '[mir4-a05-k2-materials-paving-parity]'
$packageManifestRelative='src/mod/families/modern/prototypes/mir/streams/generated_stream_manifest.json'
$rootManifestRelative='prototypes/mir/streams/generated_stream_manifest.json'
$packageManifest=Get-Content -Raw -LiteralPath (Resolve-A05K2ClosurePath $packageManifestRelative $true)|ConvertFrom-Json -Depth 30
$rootManifest=Get-Content -Raw -LiteralPath (Resolve-A05K2ClosurePath $rootManifestRelative $true)|ConvertFrom-Json -Depth 30
$reviewedForwardTechnologies=@('recipe-prod-research_material_rare_metals-1','recipe-prod-research_material_silicon-1','recipe-prod-research_material_glass-1')
Assert-A05K2Closure (@($packageManifest.streams.PSObject.Properties).Count-eq98 -and @($rootManifest.streams.PSObject.Properties).Count-eq76) '[mir4-a05-k2-materials-projection-gap]'
foreach($technology in $reviewedForwardTechnologies){$row=@($packageManifest.streams.PSObject.Properties|Where-Object{[string]$_.Value.generated_technology-ceq$technology});$rootRow=@($rootManifest.streams.PSObject.Properties|Where-Object{[string]$_.Value.generated_technology-ceq$technology});Assert-A05K2Closure ($row.Count-eq1 -and [string]$row[0].Value.policy-ceq'exact-reviewed-forward-material-manufacturing' -and $rootRow.Count-eq0) "[mir4-a05-k2-materials-reviewed-forward-manifest] $technology"}
$previousEvolutionRelative='spec/programmes/evidence/synthesis-2026-09-10/a05-k2-materials/k2-03/MIR4-A05-K2-03-Command-Inventory-EvolutionV1.json'
$previousEvolutionBinding=Get-A05K2ClosureRecordBinding $previousEvolutionRelative
$previousEvolution=Get-Content -Raw -LiteralPath (Resolve-A05K2ClosurePath $previousEvolutionRelative $true)|ConvertFrom-Json -Depth 100 -DateKind String
Assert-A05K2Closure ($previousEvolution.kind-eq'MIR4A05K203CommandInventoryEvolutionV1' -and $previousEvolution.status-eq'append-only-successor-passed' -and $previousEvolution.current.raw_sha256-eq'45CE61E163C34A6BE41A02BDB7C2A375F05ED5E1B9E09DE5C36C6564A58B72BC' -and $previousEvolution.current.canonical_sha256-eq'45CE61E163C34A6BE41A02BDB7C2A375F05ED5E1B9E09DE5C36C6564A58B72BC' -and $previousEvolution.current.digest-eq'sha256:5074415336ac8c7b45dde4f8e851071352c33d7bfbf76679882cb891eddcfd9d' -and [int]$previousEvolution.current.command_count-eq85 -and [int]$previousEvolution.current.canonical_internal_count-eq379) '[mir4-a05-k2-materials-inventory-predecessor]'

$inventoryRelative='governance/automation/mir4-command-inventory-v1.json'
Update-MIR4CommandInventoryV1 -RepoRoot $RepoRoot -Check|Out-Null
$inventoryPath=Resolve-A05K2ClosurePath $inventoryRelative $true
$inventory=Get-Content -Raw -LiteralPath $inventoryPath|ConvertFrom-Json -Depth 100 -DateKind String
$added=@($inventory.implementation_files|Where-Object path -CEQ 'tools/commands/mir4/Write-MIR4A05K2MaterialsClosure.ps1')
Assert-A05K2Closure ($inventory.command_count-eq85 -and $inventory.summary.canonical_public-eq1 -and $inventory.summary.canonical_internal-eq380 -and $inventory.summary.compatibility_wrapper-eq168 -and $inventory.summary.migration_only-eq48 -and $inventory.summary.historical-eq16 -and $inventory.summary.obsolete-eq0 -and $inventory.summary.unknown-eq0 -and $inventory.summary.duplicate_command_keys-eq0 -and $added.Count-eq1 -and $added[0].classification-eq'canonical-internal' -and -not$added[0].package_visible) '[mir4-a05-k2-materials-current-inventory]'
$predecessor=[ordered]@{schema=[int]$inventory.schema;kind=[string]$inventory.kind;state=[string]$inventory.state;public_entrypoint=[string]$inventory.public_entrypoint;router=[string]$inventory.router;command_count=[int]$inventory.command_count;commands=@($inventory.commands);implementation_files=@($inventory.implementation_files|Where-Object path -CNE 'tools/commands/mir4/Write-MIR4A05K2MaterialsClosure.ps1');summary=[ordered]@{canonical_public=1;canonical_internal=379;compatibility_wrapper=168;migration_only=48;historical=16;obsolete=0;unknown=0;duplicate_command_keys=0};transition_gate=[ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false};digest=''}
$digestMaterial=[ordered]@{}
foreach($property in $predecessor.GetEnumerator()){if([string]$property.Key-cne'digest'){$digestMaterial[$property.Key]=$property.Value}}
$predecessor.digest=Get-MIR4CommandInventoryDigestV1 -Value $digestMaterial
$predecessorText=(($predecessor|ConvertTo-Json -Depth 100)+[string][char]10).Replace(([string][char]13+[char]10),[string][char]10).Replace([string][char]13,[string][char]10)
$predecessorScratch=Join-Path $RepoRoot 'build/a05-k2-materials/reconstructed-k2-03-command-inventory.json'
[IO.File]::WriteAllText($predecessorScratch,$predecessorText,[Text.UTF8Encoding]::new($false))
$reconstructedSha=Get-MIR4Sha256File -Path $predecessorScratch
Assert-A05K2Closure ($predecessor.digest-eq[string]$previousEvolution.current.digest -and $reconstructedSha-eq[string]$previousEvolution.current.raw_sha256) '[mir4-a05-k2-materials-inventory-predecessor-reconstruction]'
$inventoryEvolution=[pscustomobject][ordered]@{schema=1;kind='MIR4A05K2MaterialsCommandInventoryEvolutionV1';recorded_at=[string]$runtime.generated_at;task='A05/K2-materials';status='append-only-successor-passed';predecessor=[pscustomobject][ordered]@{k2_03_evolution=$previousEvolutionBinding;inventory=[pscustomobject][ordered]@{path=$inventoryRelative;raw_sha256=[string]$previousEvolution.current.raw_sha256;canonical_sha256=[string]$previousEvolution.current.canonical_sha256;digest=[string]$previousEvolution.current.digest;command_count=85;canonical_internal_count=379}};current=[pscustomobject][ordered]@{path=$inventoryRelative;raw_sha256=Get-MIR4Sha256File -Path $inventoryPath;canonical_sha256=Get-MIR4BootstrapTextSha256 -Path $inventoryPath;digest=[string]$inventory.digest;command_count=85;canonical_internal_count=380};transition=[pscustomobject][ordered]@{classification='append-only-one-canonical-internal-writer';added_implementation_files=$added;reconstructed_predecessor_sha256=$reconstructedSha;public_command_count_unchanged=$true;non_added_summary_counts_unchanged=$true;transition_gates_remain_closed=$true};authority_flags=[pscustomobject][ordered]@{public_command_authority=$false;player_mutation_authorized=$false;release_authority=$false;signing_authority=$false;publication_authority=$false};record_sha256=''}
$inventoryEvolutionRelative='spec/programmes/evidence/synthesis-2026-09-10/a05-k2-materials/k2-materials/MIR4-A05-K2-Materials-Command-Inventory-EvolutionV1.json'
$inventoryEvolutionBinding=Write-A05K2EvolutionRecord $inventoryEvolution $inventoryEvolutionRelative

$sourcePaths=@('src/mod/families/modern/prototypes/mir/capabilities/recipe_productivity/recipe_matching.lua','src/mod/families/modern/prototypes/mir/index/recipe_facts.lua','src/mod/families/modern/prototypes/mir/index/recipe_risk_facts.lua','src/mod/families/modern/prototypes/mir/index/relationships.lua','src/mod/families/modern/prototypes/mir/index/item_prototype_facts.lua','src/mod/families/modern/prototypes/mir/platform/factorio/prototype_lookup.lua','src/mod/families/modern/prototypes/mir/core/fingerprint.lua','src/mod/common/prototypes/mir/core/deepcopy.lua','src/mod/common/prototypes/mir/domain/facts/recipe_semantics.lua','src/mod/common/prototypes/mir/platform/factorio/data_raw.lua','src/mod/families/modern/prototypes/mir/report/compiler_telemetry.lua','src/mod/families/modern/prototypes/mir/pipeline/compiler_context.lua','src/mod/common/prototypes/mir/settings/automatic_compiler_policy.lua','targets/f210/files/prototypes/mir/platform/factorio/target_profiles.lua','.mir/targets.json','tools/commands/targets/Sync-MIRTargetProfiles.ps1',$packageManifestRelative,$rootManifestRelative,'.mir/streams.yml','src/mod/families/modern/prototypes/streams/productivity.lua','tools/mir/application/package/TargetMaterializer.ps1','src/mod/package-source.json','targets/f210/overlay.json','targets/f200/overlay.json','targets/package-authority.json','tests/compiler/material_routes.lua','tests/runtime/Test-MIR4A05K2Materials.ps1','tests/mir4/Test-MIR4A05K2MaterialsClosure.ps1','fixtures/assert-k2-materials/info.json','fixtures/assert-k2-materials/data-final-fixes.lua','fixtures/assert-k2-materials/control.lua','tools/commands/mir4/Write-MIR4A05K2MaterialsClosure.ps1','tools/mir/application/tooling/CommandInventory.ps1','governance/automation/mir4-command-inventory-v1.json','spec/programmes/mir4-4x-operating-programme-v1.json','spec/programmes/community-requests.json','spec/schemas/mir4-a05-k2-materials-closure-v1.schema.json','spec/schemas/mir4-a05-k2-materials-command-inventory-evolution-v1.schema.json','.mir/assurance.json','.mir/fixtures.yml','.mir/modules.yml','.mir/control/paths.yml','validation/tests.yml')
$sourcePaths+=@('src/mod/families/modern/prototypes/mir/pipeline/recipe_productivity_permissions.lua','src/mod/families/modern/prototypes/mir/index/productivity_owners.lua','src/mod/families/modern/prototypes/mir/policy/competing_productivity.lua')
$qualificationBoundary=[pscustomobject][ordered]@{graph_guard='potential-return-paths-withheld-unless-exact-profile-locked-reviewed-forward-certificate-proves-bounded-ordinary-route';reviewed_forward_certificate='exact-final-recipe-facts-risk-fingerprint-and-complete-mod-profile-locked';current_k2so_material_qualification='bounded-rare-metals-silicon-glass-fresh-and-two-reload-evidence';broader_k2so_support='not-proven';angel_or_combined_a06_support='not-proven'}
$projectionGap=[pscustomobject][ordered]@{status='unresolved-pre-release';blocks_release=$true;package_source=[pscustomobject][ordered]@{path=$packageManifestRelative;rows=98;raw_sha256=Get-MIR4Sha256File -Path (Resolve-A05K2ClosurePath $packageManifestRelative $true)};root_projection=[pscustomobject][ordered]@{path=$rootManifestRelative;rows=76;raw_sha256=Get-MIR4Sha256File -Path (Resolve-A05K2ClosurePath $rootManifestRelative $true)};mir_projection_authority=Get-A05K2ClosureSource '.mir/streams.yml';required_disposition='regenerate-whole-projection-or-authoritatively-reconcile-before-release-candidate'}
$record=[pscustomobject][ordered]@{schema=1;kind='MIR4A05K2MaterialsClosureV1';recorded_at=[string]$runtime.generated_at;task='A05';requests=@('K2-02','K2-04','K2-05','K2-06','K2-07');status='bounded-claims-passed';runtime_result=Get-A05K2ClosureArtifact $runtimeRelative;candidate=$candidate;engine=$runtime.engine;command_inventory_evolution=$inventoryEvolutionBinding;source_authorities=@($sourcePaths|ForEach-Object{Get-A05K2ClosureSource $_});cases=[pscustomobject][ordered]@{locked_2_0_13=$locked;current_2_0_17=$current};qualification_boundary=$qualificationBoundary;projection_gap=$projectionGap;outcomes=[pscustomobject][ordered]@{K2_02=[pscustomobject][ordered]@{admitted_routes=@('kr-rare-metals','kr-rare-metals-from-enriched-rare-metals');technology='recipe-prod-research_material_rare_metals-1';effect_per_tier=0.02;finite_tiers=3;science=@('automation-science-pack','chemical-science-pack','logistic-science-pack')};K2_04=[pscustomobject][ordered]@{admitted_routes=@('kr-silicon');technology='recipe-prod-research_material_silicon-1';effect_per_tier=0.02;finite_tiers=3;science=@('automation-science-pack','logistic-science-pack')};K2_05=[pscustomobject][ordered]@{admitted_routes=@('kr-glass');technology='recipe-prod-research_material_glass-1';effect_per_tier=0.02;finite_tiers=3;science=@('automation-science-pack','chemical-science-pack','logistic-science-pack')};K2_06=[pscustomobject][ordered]@{withheld_recipe='kr-black-reinforced-plate';reason='final-productivity-permission-not-true-and-no-owner'};K2_07=[pscustomobject][ordered]@{withheld_recipe='kr-white-reinforced-plate';reason='final-productivity-permission-not-true-and-no-owner'};casting=[pscustomobject][ordered]@{withheld_recipe='kr-casting-rare-metals';reason='final-dirty-water-ignored-by-productivity-5'};paving=[pscustomobject][ordered]@{routes=@($locked.paving_routes);recolor_return_routes=@()}};remaining_obligations=@('Resolve the 98-row package-source versus 76-row root/static stream projection gap before release-candidate qualification.','Qualify or explicitly withhold advanced, weighted, and other K2SO processes outside the bounded material slice.','Obtain exact dependency-valid Angel-only and combined locks before A06 claims.','Design and prove meaningful infinite continuation or retain the finite-only cap explanation.');authority_flags=[pscustomobject][ordered]@{a05_complete=$false;broader_k2so_support=$false;angel_or_combined_a06_support=$false;release_authority=$false;signing_authority=$false;publication_authority=$false};non_claims=@('No casting, paving, recovery, catalyst, probabilistic, ranged, or weighted-process admission.','No infinite continuation; emitted technologies retain three finite 2% tiers.','Current K2SO 2.0.17 qualification is only the bounded rare-metals, silicon, and glass material slice with fresh and two-reload evidence; it is not broader K2SO or enhancement support.','No Angel-only or combined A06 support; retained BA rows are preliminary Bob-environment observations, not A06 completion.','No broader K2 or A05 completion, public support, release, signing, or publication authority.');record_sha256=''}
$closureBinding=Write-A05K2ClosureRecord $record 'spec/programmes/evidence/synthesis-2026-09-10/a05-k2-materials/k2-materials/MIR4-A05-K2-Materials-ClosureV1.json'
[pscustomobject][ordered]@{status='passed';closure=$closureBinding;command_inventory_evolution=$inventoryEvolutionBinding}|ConvertTo-Json -Compress
