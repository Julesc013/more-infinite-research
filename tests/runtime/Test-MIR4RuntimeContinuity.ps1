param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

function Assert-MIR4RuntimeContinuityV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$compatibilityBefore=(Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash
$providers=@(New-MIR4NormalizedTargetProviders -RepoRoot $repo)
$runtime=New-MIR4RuntimeStateMatrix -RepoRoot $repo -Providers $providers -SourceIdentity $null
$runtimeReverse=New-MIR4RuntimeStateMatrix -RepoRoot $repo -Providers @($providers|Sort-Object id -Descending) -SourceIdentity $null
$migration=New-MIR4MigrationGraphMatrix -RepoRoot $repo -Providers $providers -SourceIdentity $null
$migrationReverse=New-MIR4MigrationGraphMatrix -RepoRoot $repo -Providers @($providers|Sort-Object id -Descending) -SourceIdentity $null
$continuity=New-MIR4ContinuityBundle -RepoRoot $repo -Providers $providers -SourceIdentity $null -CandidateZip $null -RuntimeStateMatrix $runtime -MigrationGraphMatrix $migration

Assert-MIR4RuntimeContinuityV1 ($providers.Count-eq17-and@($runtime.targets).Count-eq17-and@($continuity.targets).Count-eq17) 'mir4-runtime-continuity-target-count'
Assert-MIR4RuntimeContinuityV1 ([string]$runtime.digest-ceq[string]$runtimeReverse.digest-and[string]$migration.digest-ceq[string]$migrationReverse.digest) 'mir4-runtime-continuity-order-parity'
Assert-MIR4RuntimeContinuityV1 (@($runtime.runtime_feature_specs).Count-eq7-and@($runtime.state_specs).Count-eq5-and@($runtime.registration_plan.groups).Count-eq9-and@($migration.edges).Count-eq10) 'mir4-runtime-continuity-contract-counts'
Assert-MIR4RuntimeContinuityV1 ([bool]$runtime.registration_plan.law_results.all_passed-and[bool]$migration.law_results.all_passed) 'mir4-runtime-continuity-laws'
Assert-MIR4RuntimeContinuityV1 (-not[bool]$runtime.package_visible-and-not[bool]$migration.package_visible-and-not[bool]$continuity.package_visible-and-not[bool]$runtime.runtime_mutation_authorized-and-not[bool]$migration.migration_execution_authorized-and-not[bool]$continuity.runtime_mutation_authorized) 'mir4-runtime-continuity-authority-firewall'
Assert-MIR4RuntimeContinuityV1 (-not[bool]$runtime.public_release_proof-and-not[bool]$migration.public_release_proof-and-not[bool]$continuity.public_release_proof) 'mir4-runtime-continuity-public-proof-firewall'

$record=[ordered]@{
  target_count=$providers.Count
  runtime_digest=[string]$runtime.digest
  migration_digest=[string]$migration.digest
  continuity_digest=[string]$continuity.digest
  feature_count=@($runtime.runtime_feature_specs).Count
  state_count=@($runtime.state_specs).Count
  registration_group_count=@($runtime.registration_plan.groups).Count
  migration_edge_count=@($migration.edges).Count
  runtime_laws_passed=[bool]$runtime.registration_plan.law_results.all_passed
  migration_laws_passed=[bool]$migration.law_results.all_passed
  package_visible=[bool]$runtime.package_visible-or[bool]$migration.package_visible-or[bool]$continuity.package_visible
  runtime_mutation_authorized=[bool]$runtime.runtime_mutation_authorized-or[bool]$continuity.runtime_mutation_authorized
  migration_execution_authorized=[bool]$migration.migration_execution_authorized
  public_release_proof=[bool]$runtime.public_release_proof-or[bool]$migration.public_release_proof-or[bool]$continuity.public_release_proof
}
$parity=Get-MIR4CanonicalDigestV1 -Value $record -Domain 'mir4:runtime-continuity-functional-parity:1'
Assert-MIR4RuntimeContinuityV1 ([string]$parity-ceq'sha256:5913a0d3fa7746af872bbdaa67e7f3b45bdfc82391522922f25fcc14028b45df') 'mir4-runtime-continuity-functional-parity' ([string]$parity)

$tampered=$runtime.registration_plan|ConvertTo-Json -Depth 100|ConvertFrom-Json
$tampered.groups=@($tampered.groups)+@($tampered.groups[0])
try{Assert-MIR4RuntimeRegistrationPlan -Plan $tampered|Out-Null;throw '[mir4-runtime-continuity-duplicate-registration-accepted]'}
catch{if(-not$_.Exception.Message.StartsWith('[mir4-runtime-duplicate-registration-group]')){throw}}

Assert-MIR4RuntimeContinuityV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-runtime-continuity-package-source-mutation'
Assert-MIR4RuntimeContinuityV1 ((Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash-ceq$compatibilityBefore) 'mir4-runtime-continuity-compatibility-policy-mutation'

[pscustomobject][ordered]@{status='accepted';canonical_application='tools/mir/application/runtime/RuntimeStateModel.ps1';canonical_exporter='tools/mir/cli/Export-MIR4RuntimeContinuityRecords.ps1';target_count=$providers.Count;functional_parity_digest=$parity;package_source_sha256=$packageBefore;package_visible_delta=@();release_transition_authority=$false}
