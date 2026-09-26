# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$CandidateZip='build/mir4/m4c02-target-products/packages/more-infinite-research_4.0.21000.zip'
)

$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $PSScriptRoot 'MIR4ReceiptTestSupport.ps1')
$hostedReceiptOnly=Test-MIR4HostedReceiptOnly
$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
$authority=Get-MIR4RuntimeContinuityAuthority -RepoRoot $RepoRoot
$providers=@(New-MIR4NormalizedTargetProviders -RepoRoot $RepoRoot)
$runtimeA=New-MIR4RuntimeStateMatrix -RepoRoot $RepoRoot -Providers $providers -SourceIdentity $null
$runtimeB=New-MIR4RuntimeStateMatrix -RepoRoot $RepoRoot -Providers @($providers|Sort-Object id -Descending) -SourceIdentity $null
if($runtimeA.digest-cne$runtimeB.digest){throw '[mir4-w04-runtime-determinism]'}
if(@($runtimeA.runtime_feature_specs).Count-ne 7-or@($runtimeA.state_specs).Count-ne 5-or@($runtimeA.registration_plan.groups).Count-ne 9-or@($runtimeA.targets).Count-ne 17){throw '[mir4-w04-runtime-contract-counts]'}
foreach($feature in @($runtimeA.runtime_feature_specs)){if([string]$feature.source_sha256-cne(Get-MIR4PlatformInputSha256 (Resolve-MIR4RuntimeProgrammePath -RepoRoot $RepoRoot -RelativePath ([string]$feature.source)))){throw "[mir4-w04-runtime-source-canonical-hash] $($feature.id)"}}
if([string]$runtimeA.registration_plan.owner_sha256-cne(Get-MIR4PlatformInputSha256 (Resolve-MIR4RuntimeProgrammePath -RepoRoot $RepoRoot -RelativePath ([string]$runtimeA.registration_plan.owner)))){throw '[mir4-w04-runtime-owner-canonical-hash]'}
$onLoad=$runtimeA.registration_plan.on_load;$onLoadHosts=@($onLoad.hosts)
if(-not$runtimeA.registration_plan.law_results.all_passed-or-not$onLoad.registered-or[string]$onLoad.handler-cne'passive_repair.on_load'-or-not[bool]$onLoad.read_only_restoration-or[int]$onLoad.registration_count-ne1-or$onLoad.persistent_mutation-or$runtimeA.registration_plan.on_tick.registered-or-not$runtimeA.registration_plan.filter_before_dispatch-or$onLoadHosts.Count-ne2-or(@($onLoadHosts.target|Sort-Object)-join'|')-cne'f200|f210'){throw '[mir4-w04-dispatcher-laws]'}
foreach($target in @('f210','f200')){$host=@($onLoadHosts|Where-Object target -eq $target)[0];$context=New-MIR4CurrentTargetPackageContext -RepoRoot $RepoRoot -Target $target;$dispatcher=Resolve-MIR4CurrentTargetPackageOutputPath -Context $context -RelativePath 'prototypes/mir/runtime/scripted_techs.lua';$stage=Resolve-MIR4CurrentTargetPackageOutputPath -Context $context -RelativePath 'prototypes/mir/stage/control.lua';if([string]$host.approved_handler-cne'passive_repair.on_load'-or[int]$host.registration_count-ne1-or[int]$host.approved_registration_count-ne1-or[string]$host.source_identity.dispatcher.path-cne'prototypes/mir/runtime/scripted_techs.lua'-or[string]$host.source_identity.dispatcher.sha256-cne(Get-MIR4PlatformInputSha256 $dispatcher)-or[string]$host.source_identity.stage.path-cne'prototypes/mir/stage/control.lua'-or[string]$host.source_identity.stage.sha256-cne(Get-MIR4PlatformInputSha256 $stage)){throw "[mir4-w04-on-load-host-identity] $target"}}
$f210=@($runtimeA.targets|Where-Object { $_.target -eq 'f210' })[0]
$f110=@($runtimeA.targets|Where-Object { $_.target -eq 'f110' })[0]
$f014=@($runtimeA.targets|Where-Object { $_.target -eq 'f014' })[0]
$f012=@($runtimeA.targets|Where-Object { $_.target -eq 'f012' })[0]
if($f210.backend-cne'storage'-or@($f210.feature_dispositions|Where-Object { $_.disposition -eq 'active-player-authority' }).Count-lt 6){throw '[mir4-w04-f210-runtime-profile]'}
if($f110.backend-cne'global'-or@($f110.feature_dispositions|Where-Object { $_.disposition -ne 'compiled-out' }).Count-ne 0){throw '[mir4-w04-f110-runtime-profile]'}
if(@($f014.feature_dispositions|Where-Object { $_.disposition -ne 'opaque-terminal-derived' }).Count-ne 0-or@($f012.feature_dispositions|Where-Object { $_.disposition -ne 'blocked-with-evidence' }).Count-ne 0){throw '[mir4-w04-historical-runtime-disposition]'}
$spoilage=@($runtimeA.state_specs|Where-Object { $_.id -eq 'state.spoilage-preservation' })[0]
$maximum=@($runtimeA.state_specs|Where-Object { $_.id -eq 'state.maximum-level-control' })[0]
if(@($spoilage.fields|Where-Object { $_.classification -eq 'authoritative' }).Count-ne 2-or@($maximum.fields|Where-Object { $_.classification -eq 'authoritative' }).Count-ne 2-or@($maximum.fields|Where-Object { $_.classification -eq 'disposable-cache' }).Count-ne 1){throw '[mir4-w04-field-aware-state]'}
$tampered=$runtimeA.registration_plan|ConvertTo-Json -Depth 100|ConvertFrom-Json
$tampered.groups=@($tampered.groups)+@($tampered.groups[0])
try{Assert-MIR4RuntimeRegistrationPlan -Plan $tampered|Out-Null;throw '[mir4-w04-duplicate-registration-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-runtime-duplicate-registration-group]')){throw}}
$unknownOnLoad=$runtimeA.registration_plan|ConvertTo-Json -Depth 100|ConvertFrom-Json
$unknownOnLoad.on_load.handler='unknown.on_load'
try{Assert-MIR4RuntimeRegistrationPlan -Plan $unknownOnLoad|Out-Null;throw '[mir4-w04-unknown-on-load-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-runtime-on-load-registration]')){throw}}
$duplicateOnLoad=$runtimeA.registration_plan|ConvertTo-Json -Depth 100|ConvertFrom-Json
$duplicateOnLoad.on_load.registration_count=2
try{Assert-MIR4RuntimeRegistrationPlan -Plan $duplicateOnLoad|Out-Null;throw '[mir4-w04-duplicate-on-load-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-runtime-on-load-registration]')){throw}}
$unregisteredOnLoad=$runtimeA.registration_plan|ConvertTo-Json -Depth 100|ConvertFrom-Json
$unregisteredOnLoad.owner='test/unregistered-runtime-owner.lua';$unregisteredOnLoad.on_load.registered=$false;$unregisteredOnLoad.on_load.handler=$null;$unregisteredOnLoad.on_load.read_only_restoration=$false;$unregisteredOnLoad.on_load.registration_count=0
Assert-MIR4RuntimeRegistrationPlan -Plan $unregisteredOnLoad|Out-Null
$legacyUnregistered=$runtimeA.registration_plan|ConvertTo-Json -Depth 100|ConvertFrom-Json
$legacyUnregistered.owner='test/legacy-runtime-owner.lua';$legacyUnregistered.on_load=[pscustomobject]@{registered=$false;persistent_mutation=$false}
Assert-MIR4RuntimeRegistrationPlan -Plan $legacyUnregistered|Out-Null
$missingOnLoad=$runtimeA.registration_plan|ConvertTo-Json -Depth 100|ConvertFrom-Json
$missingOnLoad.PSObject.Properties.Remove('on_load')
try{Assert-MIR4RuntimeRegistrationPlan -Plan $missingOnLoad|Out-Null;throw '[mir4-w04-missing-on-load-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-runtime-on-load-registration]')){throw}}
$missingOnTick=$runtimeA.registration_plan|ConvertTo-Json -Depth 100|ConvertFrom-Json
$missingOnTick.PSObject.Properties.Remove('on_tick')
try{Assert-MIR4RuntimeRegistrationPlan -Plan $missingOnTick|Out-Null;throw '[mir4-w04-missing-on-tick-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-runtime-idle-or-load-mutation]')){throw}}
$textReadonly=$runtimeA.registration_plan|ConvertTo-Json -Depth 100|ConvertFrom-Json
$textReadonly.on_load.read_only_restoration='false'
try{Assert-MIR4RuntimeRegistrationPlan -Plan $textReadonly|Out-Null;throw '[mir4-w04-text-readonly-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-runtime-on-load-registration]')){throw}}
foreach($inverse in @(@{name='handler';value='unknown.on_load'},@{name='registration_count';value=1},@{name='read_only_restoration';value=$true})){$invalid=$runtimeA.registration_plan|ConvertTo-Json -Depth 100|ConvertFrom-Json;$invalid.on_load.registered=$false;$invalid.on_load.($inverse.name)=$inverse.value;try{Assert-MIR4RuntimeRegistrationPlan -Plan $invalid|Out-Null;throw "[mir4-w04-unregistered-$($inverse.name)-accepted]"}catch{if(-not$_.Exception.Message.StartsWith('[mir4-runtime-on-load-registration]')){throw}}}
$invalidHost=$runtimeA.registration_plan|ConvertTo-Json -Depth 100|ConvertFrom-Json
$invalidHost.on_load.hosts[0].target='f100'
try{Assert-MIR4RuntimeRegistrationPlan -Plan $invalidHost|Out-Null;throw '[mir4-w04-invalid-on-load-host-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-runtime-on-load-registration]')){throw}}
$loadMutation=$runtimeA.registration_plan|ConvertTo-Json -Depth 100|ConvertFrom-Json
$loadMutation.on_load.persistent_mutation=$true
try{Assert-MIR4RuntimeRegistrationPlan -Plan $loadMutation|Out-Null;throw '[mir4-w04-load-mutation-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-runtime-idle-or-load-mutation]')){throw}}
$migrationA=New-MIR4MigrationGraphMatrix -RepoRoot $RepoRoot -Providers $providers -SourceIdentity $null
$migrationB=New-MIR4MigrationGraphMatrix -RepoRoot $RepoRoot -Providers @($providers|Sort-Object id -Descending) -SourceIdentity $null
if($migrationA.digest-cne$migrationB.digest-or@($migrationA.edges).Count-ne 10-or@($migrationA.edge_kinds).Count-ne 8-or-not$migrationA.law_results.all_passed-or$migrationA.complete_for_public_release){throw '[mir4-w04-migration-graph]'}
foreach($edge in @($migrationA.edges)){foreach($evidence in @($edge.evidence)){if([string]$evidence.sha256-cne(Get-MIR4PlatformInputSha256 (Resolve-MIR4RuntimeProgrammePath -RepoRoot $RepoRoot -RelativePath ([string]$evidence.path)))){throw "[mir4-w04-migration-evidence-canonical-hash] $($edge.id):$($evidence.path)"}}}
if(@($migrationA.edges|Where-Object{$_.kind-eq'downgrade'-and$_.status-eq'unsupported-with-evidence'}).Count-ne 1){throw '[mir4-w04-downgrade]'}
$candidatePath=$null
if(-not[string]::IsNullOrWhiteSpace($CandidateZip)){
  $candidateInput=if([IO.Path]::IsPathRooted($CandidateZip)){$CandidateZip}else{Join-Path $RepoRoot $CandidateZip}
  if(Test-Path -LiteralPath $candidateInput -PathType Leaf){$candidatePath=$candidateInput}
  elseif(-not$hostedReceiptOnly){throw '[mir4-w04-private-candidate-required]'}
}
$head=(& git -C $RepoRoot rev-parse HEAD).Trim();$tree=(& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim();$source=[ordered]@{commit=$head;tree=$tree;programme_id='M4C02-09-24H'}
$runtime=New-MIR4RuntimeStateMatrix -RepoRoot $RepoRoot -Providers $providers -SourceIdentity $source
$migration=New-MIR4MigrationGraphMatrix -RepoRoot $RepoRoot -Providers $providers -SourceIdentity $source
$continuity=New-MIR4ContinuityBundle -RepoRoot $RepoRoot -Providers $providers -SourceIdentity $source -CandidateZip $candidatePath -RuntimeStateMatrix $runtime -MigrationGraphMatrix $migration
if($continuity.target_count-ne 17-or-not$continuity.redaction_manifest.complete-or$continuity.package_visible-or$continuity.public_release_proof){throw '[mir4-w04-continuity-boundary]'}
$f210Package=@($continuity.package_roots|Where-Object { $_.target -eq 'f210' })[0].descriptor
if($candidatePath){if($f210Package.status-cne'present-private-unqualified'-or[string]$f210Package.sha256-cne(Get-MIR4PlatformFileSha256 $candidatePath)){throw '[mir4-w04-continuity-package-root]'}}elseif($f210Package.status-cne'not-materialized-for-this-bundle'){throw '[mir4-w04-continuity-template-package-root]'}
$laws=Test-MIR4SemanticMergeLaws -RepoRoot $RepoRoot
if(-not$laws.complete-or-not$laws.implemented_passed-or@($laws.deferred_owners).Count-ne 0-or@($laws.laws|Where-Object passed).Count-ne 12){throw '[mir4-w04-W03-law-cutover]'}
$runs=@(New-MIR4NormalizedCompilationRuns -RepoRoot $RepoRoot -Providers $providers)
if(@($runs|Where-Object{$_.runtime_state.inventory_kind-ne'MIR4RuntimeStateMatrixV1'-or$_.runtime_state.status-ne'W04-shadow-contract-complete-runtime-proof-required'-or$_.runtime_state.mutation_authorized}).Count-ne 0){throw '[mir4-w04-compilation-run-reference]'}
$output='build/mir4/test-w04-runtime-continuity'
& (Join-Path $RepoRoot 'tools/mir/cli/Export-MIR4RuntimeContinuityRecords.ps1') -RepoRoot $RepoRoot -OutputRoot $output -CandidateZip $candidatePath|Out-Null
& (Join-Path $RepoRoot 'tools/mir/cli/Export-MIR4RuntimeContinuityRecords.ps1') -RepoRoot $RepoRoot -OutputRoot $output -CandidateZip $candidatePath -Check|Out-Null
foreach($name in @('MIR4_RUNTIME_STATE_MATRIX.json','MIR4_MIGRATION_GRAPH_MATRIX.json','MIR4_CONTINUITY_BUNDLE.json')){$record=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$output/$name")|ConvertFrom-Json;if([string]$record.source_identity.commit-cne$head-or[string]$record.source_identity.tree-cne$tree-or$record.package_visible-or$record.public_release_proof){throw "[mir4-w04-export-identity] $name"};if($name-ceq'MIR4_RUNTIME_STATE_MATRIX.json'){Assert-MIR4RuntimeRegistrationPlan -Plan $record.registration_plan|Out-Null}}
foreach($path in @($authority.terminal_player_authority)) { & git -C $RepoRoot diff --quiet HEAD^ HEAD -- ([string]$path); if($LASTEXITCODE-ne 0){throw "[mir4-w04-terminal-player-delta] $path"} }
if((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot)-cne$packageBefore){throw '[mir4-w04-package-mutation]'}
Write-Host '[ok] MIR 4 W04 runtime/state matrix, dispatcher laws, migration graph, and private continuity bundle passed.'
