param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/assurance/AssuranceOfflineCustodyMigration.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

function Assert-MIR4AssuranceOfflineCustodyV1([bool]$Condition,[string]$Code,[string]$Detail=''){if(-not$Condition){throw "[$Code] $Detail"}}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$programme=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Assurance-Scale-ProgrammeV1.json')|ConvertFrom-Json -Depth 100
Assert-MIR4AssuranceOfflineCustodyV1 (($programme|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-assurance-scale-programme-v1.schema.json')) 'mir4-assurance-offline-custody-programme-schema'
foreach($flag in @('semantic_authority','evidence_ledger_authority','verification_plan_authority','player_package_mutation_authorized','prototype_write_authorized','runtime_state_mutation_authorized','migration_execution_authorized','source_freeze_authorized','production_signing_or_sealing_authorized','promotion_or_tag_authorized','network_or_upload_authorized','publication_authorized')){Assert-MIR4AssuranceOfflineCustodyV1 (-not[bool]$programme.$flag) 'mir4-assurance-offline-custody-authority-firewall' $flag}
$parity=Test-MIR4AssuranceOfflineCustodyFunctionalParityV1 -RepoRoot $repo
Assert-MIR4AssuranceOfflineCustodyV1 ([string]$parity.digest-ceq$script:MIR4AssuranceOfflineCustodyPreCutoverDigestV1) 'mir4-assurance-offline-custody-pre-cutover-parity'
Assert-MIR4AssuranceOfflineCustodyV1 ([int]$parity.record.w08.critical_path.seconds-eq10-and@($parity.record.w08.proof_cover.selected).Count-eq2-and@($parity.record.w08.recovery.pending).Count-eq1) 'mir4-assurance-offline-custody-w08-shape'
Assert-MIR4AssuranceOfflineCustodyV1 ([bool]$parity.record.custody.descendant-and-not[bool]$parity.record.custody.sibling-and[string]$parity.record.custody.invalid_mode-match'only.*proof-only') 'mir4-assurance-offline-custody-boundary-shape'
Assert-MIR4AssuranceOfflineCustodyV1 (Test-MIR4AssuranceV4PreservationOrFinalMileSuccessorV1 -RepoRoot $repo) 'mir4-assurance-offline-custody-assurance-v4'
Assert-MIR4AssuranceOfflineCustodyV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-assurance-offline-custody-package-mutation'
[pscustomobject][ordered]@{status='accepted';functional_parity_digest=[string]$parity.digest;critical_path_seconds=10;environment_target_count=2;compatibility_entrypoint_count=7;package_source_sha256=$packageBefore;package_visible=$false;release_transition_authority=$false}
