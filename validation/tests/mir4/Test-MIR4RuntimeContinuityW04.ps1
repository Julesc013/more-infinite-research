param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$CandidateZip='build/mir4/m4c02-target-products/packages/more-infinite-research_4.0.21000.zip'
)

$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
$authority=Get-MIR4RuntimeContinuityAuthority -RepoRoot $RepoRoot
$providers=@(New-MIR4NormalizedTargetProviders -RepoRoot $RepoRoot)
$runtimeA=New-MIR4RuntimeStateMatrix -RepoRoot $RepoRoot -Providers $providers -SourceIdentity $null
$runtimeB=New-MIR4RuntimeStateMatrix -RepoRoot $RepoRoot -Providers @($providers|Sort-Object id -Descending) -SourceIdentity $null
if($runtimeA.digest-cne$runtimeB.digest){throw '[mir4-w04-runtime-determinism]'}
if(@($runtimeA.runtime_feature_specs).Count-ne 7-or@($runtimeA.state_specs).Count-ne 5-or@($runtimeA.registration_plan.groups).Count-ne 9-or@($runtimeA.targets).Count-ne 17){throw '[mir4-w04-runtime-contract-counts]'}
if(-not$runtimeA.registration_plan.law_results.all_passed-or$runtimeA.registration_plan.on_load.registered-or$runtimeA.registration_plan.on_tick.registered-or-not$runtimeA.registration_plan.filter_before_dispatch){throw '[mir4-w04-dispatcher-laws]'}
$f210=@($runtimeA.targets|Where-Object target -eq'f210')[0]
$f110=@($runtimeA.targets|Where-Object target -eq'f110')[0]
$f014=@($runtimeA.targets|Where-Object target -eq'f014')[0]
$f012=@($runtimeA.targets|Where-Object target -eq'f012')[0]
if($f210.backend-cne'storage'-or@($f210.feature_dispositions|Where-Object disposition -eq'active-player-authority').Count-lt 6){throw '[mir4-w04-f210-runtime-profile]'}
if($f110.backend-cne'global'-or@($f110.feature_dispositions|Where-Object disposition -ne'compiled-out').Count-ne 0){throw '[mir4-w04-f110-runtime-profile]'}
if(@($f014.feature_dispositions|Where-Object disposition -ne'opaque-terminal-derived').Count-ne 0-or@($f012.feature_dispositions|Where-Object disposition -ne'blocked-with-evidence').Count-ne 0){throw '[mir4-w04-historical-runtime-disposition]'}
$spoilage=@($runtimeA.state_specs|Where-Object id -eq'state.spoilage-preservation')[0]
$maximum=@($runtimeA.state_specs|Where-Object id -eq'state.maximum-level-control')[0]
if(@($spoilage.fields|Where-Object classification -eq'authoritative').Count-ne 2-or@($maximum.fields|Where-Object classification -eq'authoritative').Count-ne 2-or@($maximum.fields|Where-Object classification -eq'disposable-cache').Count-ne 1){throw '[mir4-w04-field-aware-state]'}
$tampered=$runtimeA.registration_plan|ConvertTo-Json -Depth 100|ConvertFrom-Json
$tampered.groups=@($tampered.groups)+@($tampered.groups[0])
try{Assert-MIR4RuntimeRegistrationPlan -Plan $tampered|Out-Null;throw '[mir4-w04-duplicate-registration-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-runtime-duplicate-registration-group]')){throw}}
$migrationA=New-MIR4MigrationGraphMatrix -RepoRoot $RepoRoot -Providers $providers -SourceIdentity $null
$migrationB=New-MIR4MigrationGraphMatrix -RepoRoot $RepoRoot -Providers @($providers|Sort-Object id -Descending) -SourceIdentity $null
if($migrationA.digest-cne$migrationB.digest-or@($migrationA.edges).Count-ne 10-or@($migrationA.edge_kinds).Count-ne 8-or-not$migrationA.law_results.all_passed-or$migrationA.complete_for_public_release){throw '[mir4-w04-migration-graph]'}
if(@($migrationA.edges|Where-Object{$_.kind-eq'downgrade'-and$_.status-eq'unsupported-with-evidence'}).Count-ne 1){throw '[mir4-w04-downgrade]'}
$candidatePath=$null
if(-not[string]::IsNullOrWhiteSpace($CandidateZip)){
  $candidatePath=if([IO.Path]::IsPathRooted($CandidateZip)){$CandidateZip}else{Join-Path $RepoRoot $CandidateZip}
  if(-not(Test-Path -LiteralPath $candidatePath -PathType Leaf)){throw '[mir4-w04-private-candidate-required]'}
}
$head=(& git -C $RepoRoot rev-parse HEAD).Trim();$tree=(& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim();$source=[ordered]@{commit=$head;tree=$tree;programme_id='M4C02-09-24H'}
$runtime=New-MIR4RuntimeStateMatrix -RepoRoot $RepoRoot -Providers $providers -SourceIdentity $source
$migration=New-MIR4MigrationGraphMatrix -RepoRoot $RepoRoot -Providers $providers -SourceIdentity $source
$continuity=New-MIR4ContinuityBundle -RepoRoot $RepoRoot -Providers $providers -SourceIdentity $source -CandidateZip $candidatePath -RuntimeStateMatrix $runtime -MigrationGraphMatrix $migration
if($continuity.target_count-ne 17-or-not$continuity.redaction_manifest.complete-or$continuity.package_visible-or$continuity.public_release_proof){throw '[mir4-w04-continuity-boundary]'}
$f210Package=@($continuity.package_roots|Where-Object target -eq'f210')[0].descriptor
if($candidatePath){if($f210Package.status-cne'present-private-unqualified'-or[string]$f210Package.sha256-cne(Get-MIR4PlatformFileSha256 $candidatePath)){throw '[mir4-w04-continuity-package-root]'}}elseif($f210Package.status-cne'not-materialized-for-this-bundle'){throw '[mir4-w04-continuity-template-package-root]'}
$laws=Test-MIR4SemanticMergeLaws -RepoRoot $RepoRoot
if(-not$laws.complete-or-not$laws.implemented_passed-or@($laws.deferred_owners).Count-ne 0-or@($laws.laws|Where-Object passed).Count-ne 12){throw '[mir4-w04-W03-law-cutover]'}
$runs=@(New-MIR4NormalizedCompilationRuns -RepoRoot $RepoRoot -Providers $providers)
if(@($runs|Where-Object{$_.runtime_state.inventory_kind-ne'MIR4RuntimeStateMatrixV1'-or$_.runtime_state.status-ne'W04-shadow-contract-complete-runtime-proof-required'-or$_.runtime_state.mutation_authorized}).Count-ne 0){throw '[mir4-w04-compilation-run-reference]'}
$output='build/mir4/test-w04-runtime-continuity'
& (Join-Path $RepoRoot 'tools/commands/mir4/Export-MIR4RuntimeContinuityRecords.ps1') -RepoRoot $RepoRoot -OutputRoot $output -CandidateZip $candidatePath|Out-Null
& (Join-Path $RepoRoot 'tools/commands/mir4/Export-MIR4RuntimeContinuityRecords.ps1') -RepoRoot $RepoRoot -OutputRoot $output -CandidateZip $candidatePath -Check|Out-Null
foreach($name in @('MIR4_RUNTIME_STATE_MATRIX.json','MIR4_MIGRATION_GRAPH_MATRIX.json','MIR4_CONTINUITY_BUNDLE.json')){$record=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$output/$name")|ConvertFrom-Json;if([string]$record.source_identity.commit-cne$head-or[string]$record.source_identity.tree-cne$tree-or$record.package_visible-or$record.public_release_proof){throw "[mir4-w04-export-identity] $name"}}
foreach($path in @($authority.terminal_player_authority)) { & git -C $RepoRoot diff --quiet HEAD^ HEAD -- ([string]$path); if($LASTEXITCODE-ne 0){throw "[mir4-w04-terminal-player-delta] $path"} }
if((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot)-cne$packageBefore){throw '[mir4-w04-package-mutation]'}
Write-Host '[ok] MIR 4 W04 runtime/state matrix, dispatcher laws, migration graph, and private continuity bundle passed.'
