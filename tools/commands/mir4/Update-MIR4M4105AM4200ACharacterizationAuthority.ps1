[CmdletBinding()]
param([string]$RepoRoot='',[string]$RecordedAt='',[switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($RepoRoot)){$RepoRoot=(Resolve-Path(Join-Path $PSScriptRoot '../../..')).Path}else{$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path}

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/repository/RepositoryCharacterization.ps1')

$outputRelative='releases/migrations/MIR4-M41-05A-M42-00A-Repository-Characterization-Authority-EvolutionV1.json'
$schemaRelative='contracts/repository/mir4-m41-05a-m42-00a-repository-characterization-authority-evolution-v1.schema.json'
$predecessorRelative='releases/migrations/MIR4-M41-03-Change-And-Release-Authority-EvolutionV1.json'
$predecessorSha256='8E992F205387851BDA5A6C315DBDD0C156CFA6D30AA1E2A7D9D9217D8A7E916E'
$expectedPackage='8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'
$expectedReadme='DF5D4D801DC4A416E4F7C9826EB2E3AE6CFD915937C8599CA7307CCEB343F947'

$state=Get-MIR4PreFreezeAuthorityState -RepoRoot $RepoRoot -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration -IncludeInspectorCompatibilityMigration -IncludeAssuranceOfflineCustodyMigration -IncludeHistoricalToolingMigration -IncludeReleaseToolingMigration -IncludeF210QualificationPolicyEvolution -IncludeFinalMileToolingEvolution -IncludeFinalReleaseClosureEvolution -IncludePostReleasePackageBaselineEvolution -IncludePostReleaseAutomationCutover -IncludePostReleaseBranchOperatingModel -IncludePostReleasePatchLaneRehearsal -IncludeM4103ChangeReleaseAuthority
if([string]$state.prior_receipt_path-cne$predecessorRelative-or[string]$state.prior_receipt_sha256-cne$predecessorSha256){throw '[mir4-m41-05a-m42-00a-predecessor]'}
if((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot)-cne$expectedPackage){throw '[mir4-m41-05a-m42-00a-package-source]'}
if((Get-MIRFileContentSha256 -Path(Join-Path $RepoRoot 'README.md') -RelativePath 'README.md')-cne$expectedReadme){throw '[mir4-m41-05a-m42-00a-readme]'}

$roles=[ordered]@{
  '.mir/assurance.json'='Register the bounded characterization proof and impact class.'
  '.mir/control/paths.yml'='Expose characterization through the canonical path registry.'
  '.mir/control/repository-fixed-point.json'='Append the characterization migration successor.'
  '.mir/docs.yml'='Regenerate the documentation metadata projection.'
  '.mir/modules.yml'='Declare the package-excluded characterization boundary.'
  'changes/unreleased/MIR4-CHG-2026-0002.json'='Accepted repository-only change authority.'
  'contracts/repository/mir4-repository-characterization-authority-v1.schema.json'='Characterization authority contract.'
  'contracts/repository/mir4-repository-characterization-bundle-v1.schema.json'='Generated bundle contract.'
  'contracts/repository/mir4-m41-05a-m42-00a-repository-characterization-authority-evolution-v1.schema.json'='Authority evolution receipt contract.'
  'governance/repository/migrations/repository-characterization-v1.json'='Canonical characterization migration authority.'
  'governance/.mir-root.json'='Regenerated governance root projection with the characterization authority.'
  'docs/README.md'='Route MIR 4 documentation by reader and need.'
  'docs/user/README.md'='Route current player documentation.'
  'docs/maintainer/README.md'='Route current maintainer procedures.'
  'docs/reference/README.md'='Route current exact reference material.'
  'docs/tutorials/README.md'='Tutorial documentation route.'
  'docs/how-to/README.md'='How-to documentation route.'
  'docs/explanation/README.md'='Explanation documentation route.'
  'docs/architecture/mir4-repository-characterization.md'='Characterization boundary explanation.'
  'docs/maintainer/mir4-authority-map.md'='Generated-ledger authority routing page.'
  'docs/architecture/module-boundaries.md'='Document the read-only characterization boundary.'
  'docs/releases/mir4-post-4.0-roadmap.md'='Record M41-05A and M42-00A disposition.'
  'docs/reference/generated/documentation-index.md'='Regenerated documentation index.'
  'docs/reference/generated/documentation-navigation.md'='Regenerated documentation navigation.'
  'docs/reference/generated/documentation-owner-dashboard.md'='Regenerated documentation owner dashboard.'
  'docs/reference/generated/documentation-review-age.md'='Regenerated documentation review-age projection.'
  'docs/reference/generated/documentation-reference-matrix.md'='Regenerated documentation reference matrix.'
  'spec/programmes/mir4-4x-operating-programme-v1.json'='Activate the two bounded subpackages without closing their parents.'
  'tests/repository/Test-MIR4RepositoryFixedPoint.ps1'='Advance repository fixed-point successor proof.'
  'tools/lib/mir4/PreFreezeRelease.ps1'='Append the characterization authority receipt to the chain.'
  'tools/mir/application/repository/RepositoryCharacterization.ps1'='Sole deterministic report writer.'
  'tools/mir/cli/Invoke-MIR4RepositoryFixedPoint.ps1'='Extend the existing repository command adapter.'
  'tools/mir/domain/repository/RepositoryFixedPoint.ps1'='Recognize the characterization successor.'
  'tools/mir.ps1'='Expose characterization on the one public command surface.'
  'tools/commands/mir4/Update-MIR4M4105AM4200ACharacterizationAuthority.ps1'='Bounded authority receipt writer.'
  'validation/tests/mir4/Test-MIR4RepositoryCharacterizationM4200A.ps1'='Executable characterization proof.'
  'validation/tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1'='Bind the expanded post-release proof profile.'
  'validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1'='Require the characterization authority successor.'
  'validation/tests.yml'='Register the executable characterization proof.'
}
$evolved=[Collections.Generic.List[object]]::new();$current=[Collections.Generic.List[object]]::new()
foreach($entry in $roles.GetEnumerator()){
  $path=[string]$entry.Key;$full=Join-Path $RepoRoot $path
  if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "[mir4-m41-05a-m42-00a-missing] $path"}
  if($state.authority_hashes.ContainsKey($path)){
    $mode=if($state.authority_hash_modes.ContainsKey($path)){[string]$state.authority_hash_modes[$path]}else{'raw-bytes'}
    $currentSha=Get-MIR4PreFreezeFileSha256 -Path $full -Mode $mode;$previousSha=[string]$state.authority_hashes[$path]
    if($currentSha-ceq$previousSha){throw "[mir4-m41-05a-m42-00a-unchanged] $path"}
    $evolved.Add([ordered]@{path=$path;previous_sha256=$previousSha;current_sha256=$currentSha;reason=[string]$entry.Value;scope='package-excluded-documentation-and-characterization';package_visible=$false;release_authority=$false})
  }else{
    $current.Add([ordered]@{path=$path;sha256=(Get-MIR4PreFreezeFileSha256 -Path $full -Mode 'canonical-text-v1');hash_mode='canonical-text-v1';role=[string]$entry.Value})
  }
}

$outputPath=Join-Path $RepoRoot $outputRelative
if($Check){
  if(-not(Test-Path -LiteralPath $outputPath -PathType Leaf)){throw '[mir4-m41-05a-m42-00a-receipt-missing]'}
  $existing=Get-Content -Raw -LiteralPath $outputPath|ConvertFrom-Json -Depth 100 -DateKind String;$RecordedAt=[string]$existing.recorded_at
}else{
  if([string]::IsNullOrWhiteSpace($RecordedAt)){$RecordedAt=[DateTimeOffset]::Now.ToString('o')}
  if(-not(Test-Path -LiteralPath $outputPath -PathType Leaf)){[void](New-Item -ItemType Directory -Force -Path(Split-Path -Parent $outputPath));[IO.File]::WriteAllText($outputPath,"{}`n",[Text.UTF8Encoding]::new($false))}
}

$characterization=Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $RepoRoot -OutputPath 'build/reports/repository-characterization'
[void](Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $RepoRoot -OutputPath 'build/reports/repository-characterization' -Check)
$manifestPath=Join-Path $RepoRoot 'build/reports/repository-characterization/manifest.json'
$proof=[ordered]@{manifest_sha256=(Get-MIR4PreFreezeFileSha256 -Path $manifestPath -Mode 'canonical-text-v1');reports=[int]$characterization.reports;physical_files=[int]$characterization.summary.physical_files;authority_facts=[int]$characterization.summary.authority_facts;current_bindings=[int]$characterization.summary.current_bindings;writers=[int]$characterization.summary.writers;readers=[int]$characterization.summary.readers;bridges=[int]$characterization.summary.bridges;package_files=[int]$characterization.summary.package_files}

$receipt=[ordered]@{
  schema=1;kind='MIR4M4105AM4200ARepositoryCharacterizationAuthorityEvolutionV1';recorded_at=$RecordedAt;programme_id='M41-05A-M42-00A-REPOSITORY-CHARACTERIZATION';change_id='MIR4-CHG-2026-0002'
  predecessor_receipt=[ordered]@{path=$predecessorRelative;sha256=$predecessorSha256}
  base=[ordered]@{branch='dev';commit='c8ef730b307af184d542ae1cc70a1b8ff31e1225';tree='472f3fba107fc9392977dea5852af038d3154ac9'}
  evolved_bindings=@($evolved);current_authorities=@($current);characterization_proof=$proof
  player_package_source_sha256=$expectedPackage;root_readme_sha256=$expectedReadme;package_visible_delta=@()
  invariants=[ordered]@{package_excluded_documentation_routed=$true;declared_authorities_ingested=$true;deterministic_reports=$true;zero_unknown_paths=$true;zero_duplicate_current_bindings=$true;all_bridges_retained=$true;package_source_unchanged=$true;root_readme_byte_stable=$true}
  transition_gate=[ordered]@{merge=$false;source_move=$false;package_cutover=$false;readme_rewrite=$false;bridge_retirement=$false;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false;remote_write=$false}
  status='M41-05A-M42-00A-CHARACTERIZATION-COMPLETE-NO-PACKAGE-CUTOVER'
}
$json=(($receipt|ConvertTo-Json -Depth 60).Replace("`r`n","`n")+"`n")
if($Check){if([IO.File]::ReadAllText($outputPath).Replace("`r`n","`n")-cne$json){throw '[mir4-m41-05a-m42-00a-receipt-stale]'}}else{[IO.File]::WriteAllText($outputPath,$json,[Text.UTF8Encoding]::new($false))}
if(-not((Get-Content -Raw -LiteralPath $outputPath)|Test-Json -SchemaFile(Join-Path $RepoRoot $schemaRelative))){throw '[mir4-m41-05a-m42-00a-receipt-schema]'}
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;evolved_bindings=$evolved.Count;current_authorities=$current.Count;characterization=$proof;package_source_sha256=$expectedPackage;root_readme_sha256=$expectedReadme}
