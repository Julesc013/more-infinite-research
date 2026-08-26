param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/lib/mir4/HistoricalSuccession.ps1')
. (Join-Path $repo 'tools/lib/mir4/SuccessorHost.ps1')
$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
Assert-MIR4PackagePresentationV1 -RepoRoot $repo -PackageSourceSha256 $packageBefore|Out-Null
$authority=Get-MIR4W09Authority -RepoRoot $repo
if(@($authority.outputs).Count-ne 2-or@($authority.historical_targets).Count-ne 6-or@($authority.museum_targets).Count-ne 7-or[string]$authority.successor_target-cne'f300'){throw '[mir4-w09-authority-shape]'}
foreach($flag in @('package_visible','semantic_authority','target_policy_authority','museum_admission_authority','rights_or_custody_authority','player_package_mutation_authorized','prototype_write_authorized','runtime_state_mutation_authorized','migration_execution_authorized','source_freeze_authorized','production_signing_or_sealing_authorized','promotion_or_tag_authorized','network_or_upload_authorized','publication_authorized')){if([bool]$authority.$flag){throw "[mir4-w09-boundary] $flag"}}

$source=[pscustomobject][ordered]@{commit=(& git -C $repo rev-parse HEAD).Trim();tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()}
$matrixA=New-MIR4HistoricalMuseumMatrixV1 -RepoRoot $repo -SourceIdentity $source
$matrixB=New-MIR4HistoricalMuseumMatrixV1 -RepoRoot $repo -SourceIdentity $source
if((ConvertTo-MIR4PlatformCanonicalJson $matrixA)-cne(ConvertTo-MIR4PlatformCanonicalJson $matrixB)){throw '[mir4-w09-matrix-determinism]'}
if(-not(($matrixA|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-historical-museum-matrix-v1.schema.json'))-or[string]$matrixA.record_sha256-cne(Get-MIR4W09RecordSha256 $matrixA)){throw '[mir4-w09-matrix-schema-or-hash]'}
if(@($matrixA.historical_targets).Count-ne 6-or@($matrixA.museum_targets).Count-ne 7-or@($matrixA.museum_targets|Where-Object maturity -ne 'blocked-museum-inventory').Count-or@($matrixA.museum_targets|Where-Object registry_disposition -ne 'deferred-museum').Count){throw '[mir4-w09-matrix-target-policy-drift]'}
$f018=@($matrixA.historical_targets|Where-Object target -eq f018)[0]
if('BLOCKED-MISSING-EXACT-ENGINE'-notin@($f018.blockers)-or[bool]$f018.candidate.publication_authorized){throw '[mir4-w09-f018-boundary]'}
if(@($matrixA.museum_targets|Where-Object{'BLOCKED-MUSEUM-RIGHTS-CUSTODY-RESTORE-CLOSURE'-notin@($_.blockers)}).Count-or@($matrixA.museum_targets|Where-Object{$_.rights_custody.redistribution_authorized-or$_.rights_custody.public_support_authorized}).Count){throw '[mir4-w09-museum-custody-boundary]'}
if((ConvertTo-MIR4PlatformCanonicalJson $matrixA)-match'(?i)[A-Z]:[/\\]'){throw '[mir4-w09-portable-record-path]'}

$out='build/mir4/test-w09-historical-succession'
$successorA=New-MIR4SuccessorHostResultV1 -RepoRoot $repo -SourceIdentity $source -OutputRoot $out
$successorB=New-MIR4SuccessorHostResultV1 -RepoRoot $repo -SourceIdentity $source -OutputRoot $out
if((ConvertTo-MIR4PlatformCanonicalJson $successorA)-cne(ConvertTo-MIR4PlatformCanonicalJson $successorB)){throw '[mir4-w09-successor-determinism]'}
if(-not(($successorA|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-successor-host-result-v1.schema.json'))-or[string]$successorA.record_sha256-cne(Get-MIR4W09RecordSha256 $successorA)){throw '[mir4-w09-successor-schema-or-hash]'}
if(-not$successorA.module_index.reviewed_only-or$successorA.module_index.network_calls-ne 0-or-not$successorA.extension_closure.complete-or-not$successorA.external_target_provider.deterministic-or-not$successorA.external_target_provider.idempotent-or-not$successorA.external_target_provider.unowned_fields_preserved-or-not$successorA.external_target_provider.forbidden_write_rejected){throw '[mir4-w09-module-provider-conformance]'}
if(-not$successorA.continuity_import.copied-or-not$successorA.continuity_import.redaction_complete-or$successorA.continuity_import.runtime_state_mutated-or$successorA.continuity_import.migration_executed-or$successorA.extension_transport.callbacks-or$successorA.extension_transport.prototype_write-or$successorA.extension_transport.runtime_mutation){throw '[mir4-w09-successor-firewall]'}
if(-not$successorA.proof_replay.deterministic-or-not$successorA.proof_replay.tamper_rejected-or-not$successorA.package_reconstruction.deterministic-or$successorA.package_reconstruction.player_package-or$successorA.package_reconstruction.production_candidate-or$successorA.package_reconstruction.publication_authorized){throw '[mir4-w09-replay-reconstruction]'}
$witness=$successorA.succession_witness
if(@($witness.changed_package_roots).Count-ne 14-or-not$witness.append_only-or$witness.prior_release_evidence_mutated-or-not$witness.published_predecessor.evidence_valid_for_predecessor-or$witness.evidence_disposition.c35_revoked-or$witness.evidence_disposition.transferable_to_mir4-or[string]$witness.published_predecessor.package_source_sha256-cne'FFF55368B65766D29049DF8E4DC845B38A6D4A65F1512EE62D277AD796181F89'-or[string]$witness.current_mir4.package_source_sha256-cne$packageBefore){throw '[mir4-w09-succession-witness]'}
foreach($blocker in @('BLOCKED-HUMAN-SECRET-INPUT','BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER','BLOCKED-EXACT-ARCHIVE-CUSTODY-F200-K2SO','BLOCKED-MUSEUM-RIGHTS-CUSTODY-RESTORE-CLOSURE','BLOCKED-FUTURE-INDEPENDENT-PRODUCTION-HOST')){if($blocker-notin@($successorA.blockers)){throw "[mir4-w09-blocker] $blocker"}}

foreach($file in @('tools/lib/mir4/HistoricalSuccession.ps1','tools/lib/mir4/SuccessorHost.ps1','tools/commands/mir4/Export-MIR4HistoricalSuccessionRecords.ps1')){$text=Get-Content -Raw -LiteralPath (Join-Path $repo $file);if($text-match'(?i)publication_authorized\s*=\s*\$true|source_freeze_authorized\s*=\s*\$true|production_signing_or_sealing_authorized\s*=\s*\$true|Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|System\.Net\.Http'){throw "[mir4-w09-capability-leak] $file"}}
if((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-cne$packageBefore){throw '[mir4-w09-package-mutation]'}
Write-Host '[ok] MIR 4 W09 historical/museum inventory, exact blockers, offline closure, synthetic external provider, successor-host replay/reconstruction, and append-only succession witness passed.'
