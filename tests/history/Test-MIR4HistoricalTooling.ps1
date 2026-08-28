param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/history/HistoricalToolingMigration.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

function Assert-MIR4HistoricalToolingV1([bool]$Condition,[string]$Code,[string]$Detail=''){if(-not$Condition){throw "[$Code] $Detail"}}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$programme=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/releases/waves/mir4-r0/MIR4-Historical-Succession-ProgrammeV1.json'
Assert-MIR4HistoricalToolingV1 (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path '.mir/releases/waves/mir4-r0/MIR4-Historical-Succession-ProgrammeV1.json' -SchemaPath 'spec/schemas/mir4-historical-succession-programme-v1.schema.json') 'mir4-historical-tooling-programme-schema'
foreach($flag in @('package_visible','semantic_authority','target_policy_authority','museum_admission_authority','rights_or_custody_authority','player_package_mutation_authorized','prototype_write_authorized','runtime_state_mutation_authorized','migration_execution_authorized','source_freeze_authorized','production_signing_or_sealing_authorized','promotion_or_tag_authorized','network_or_upload_authorized','publication_authorized')){Assert-MIR4HistoricalToolingV1 (-not[bool]$programme.$flag) 'mir4-historical-tooling-authority-firewall' $flag}
$parity=Test-MIR4HistoricalToolingFunctionalParityV1 -RepoRoot $repo
$proof=Get-MIR4HistoricalToolingMigrationProofPolicyV1 -RepoRoot $repo
Assert-MIR4HistoricalToolingV1 ([string]$proof.pre_cutover_functional_digest-ceq$script:MIR4HistoricalToolingPreCutoverDigestV1-and[string]$proof.pre_cutover_archive_content_sha256-ceq$script:MIR4HistoricalToolingArchiveContentSha256V1) 'mir4-historical-tooling-pre-cutover-evidence'
Assert-MIR4HistoricalToolingV1 ([string]$parity.digest-ceq$script:MIR4HistoricalToolingParityDigestV1) 'mir4-historical-tooling-functional-parity'
Assert-MIR4HistoricalToolingV1 ([string]$parity.record.archive.content_sha256-ceq$script:MIR4HistoricalToolingArchiveContentSha256V1-and[int]$parity.record.archive.uncompressed_bytes-eq1029-and[int]$parity.record.archive.entry_count-eq3) 'mir4-historical-tooling-archive-content'
Assert-MIR4HistoricalToolingV1 ([int]$parity.record.authority.historical_target_count-eq6-and[int]$parity.record.authority.museum_target_count-eq7-and-not[bool]$parity.record.authority.package_visible) 'mir4-historical-tooling-authority-shape'
Assert-MIR4HistoricalToolingV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-historical-tooling-package-mutation'
[pscustomobject][ordered]@{status='accepted';functional_parity_digest=[string]$parity.digest;historical_target_count=6;museum_target_count=7;compatibility_entrypoint_count=3;package_source_sha256=$packageBefore;package_visible=$false;release_transition_authority=$false}
