param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
$authority=Get-MIR4ProcessIRSynthesisAuthority -RepoRoot $RepoRoot
if(@($authority.process_ir_fields).Count-ne 14-or@($authority.candidate_constructors).Count-ne 10-or@($authority.terminal_dispositions).Count-ne 5-or@($authority.modes).Count-ne 3-or@($authority.effect_channels).Count-ne 6){throw '[mir4-w06-authority-counts]'}
if($authority.semantic_authority-or$authority.canonical_recipe_fact_authority-or$authority.canonical_risk_fact_authority-or$authority.player_mutation_authorized-or$authority.prototype_write_authorized-or$authority.runtime_state_mutation_authorized-or$authority.migration_execution_authorized-or$authority.planner_or_emitter_admission_authorized-or$authority.safety_kernel_override_authorized-or$authority.public_support_authorized-or$authority.signing_or_sealing_authorized-or$authority.publication_authorized){throw '[mir4-w06-authority-boundary]'}
if([string]$authority.exact_target_snapshot.status-cne'CAPTURED-EXACT-F210-F200-PROCESSIR-PREVIEW-WITH-DECLARED-CUSTODY-BLOCKER'-or[string]$authority.exact_target_snapshot.custody_blocker-cne'BLOCKED-EXACT-ARCHIVE-CUSTODY-F200-K2SO'){throw '[mir4-w06-exact-target-authority]'}

$records=New-MIR4W06Records -RepoRoot $RepoRoot -SourceIdentity $null
if(-not$records.parity.passed-or-not$records.parity.bilateral_gate.passed-or$records.parity.bilateral_gate.reject_everything){throw '[mir4-w06-bilateral-gate]'}
if([string]$records.parity.scope-cne'bilateral-synthetic-plus-exact-target-preview'-or[string]$records.parity.exact_target_status-cne'CAPTURED-EXACT-F210-F200-PROCESSIR-PREVIEW-WITH-DECLARED-CUSTODY-BLOCKER'-or-not$records.parity.exact_target_evidence.deterministic-or-not$records.parity.exact_target_evidence.package_source_unchanged-or$records.parity.exact_target_evidence.authoritative-or$records.parity.exact_target_evidence.public_release_proof){throw '[mir4-w06-parity-scope]'}
foreach($path in @('sdk/preview/mir4/reference/t12/MIR4_T12_RECEIPT.json','sdk/preview/mir4/reference/t12/MIR4_T12_EXACT_PROCESSIR_MANIFEST.json')){if($path-notin@($records.parity.evidence_refs.path)){throw "[mir4-w06-exact-evidence-ref] $path"}}
if(-not$records.parity.risk_parity.passed-or-not$records.parity.risk_parity.copied_not_reclassified){throw '[mir4-w06-risk-parity]'}
if(@($records.parity.fixture_results|Where-Object{-not$_.passed}).Count-ne 0){throw '[mir4-w06-fixture-result]'}
foreach($evidence in @($records.parity.evidence_refs)){if([string]$evidence.sha256-cne(Get-MIR4PlatformInputSha256 (Join-Path $RepoRoot ([string]$evidence.path)))){throw "[mir4-w06-fixture-canonical-hash] $($evidence.path)"}}

$complex=$records.fixture_irs['catalyst-container-bounded-cycle']
if(@($complex.processes|Where-Object{$_.catalysts.Count-gt 0}).Count-ne 1-or@($complex.processes|Where-Object{$_.returned_containers.Count-gt 0}).Count-ne 1-or@($complex.processes|Where-Object{$_.productivity_sensitive}).Count-ne 1-or@($complex.processes|Where-Object{$_.self_intersection.Count-gt 0}).Count-ne 1){throw '[mir4-w06-process-shape]'}
if(@($complex.sccs).Count-ne 1-or[string]$complex.sccs[0].classification-cne'CERTIFIED_BOUNDED'-or@($complex.sccs[0].minimal_witness).Count-lt 2-or$complex.sccs[0].witness_edge_count-lt 1){throw '[mir4-w06-scc-bounded-witness]'}
$routes=$records.fixture_irs['recycling-recovery']
if(@($routes.processes|Where-Object basic_recycling).Count-ne 1-or@($routes.processes|Where-Object basic_recovery).Count-ne 1){throw '[mir4-w06-recycling-recovery]'}
$unsafe=$records.fixture_irs['unbounded-positive-cycle']
if([string]$unsafe.overall_classification-cne'UNSAFE'-or[string]$unsafe.terminal_disposition-cne'FailHardSafety'-or[string]$unsafe.processes[0].safety_status-cne'rejected'){throw '[mir4-w06-known-unsafe]'}
$unknown=$records.fixture_irs['unsupported-unknown']
if([string]$unknown.overall_classification-cne'UNKNOWN'-or[string]$unknown.terminal_disposition-cne'RequestReview'-or[string]$unknown.processes[0].safety_status-cne'not-evaluated-unknown'){throw '[mir4-w06-unknown]'}
$safeInput=Read-MIR4CanonicalRecipeFactInputV1 -RepoRoot $RepoRoot -Path 'fixtures/mir4-process-ir-v1/positive/ordinary-safe.json'
$lessCertain=$safeInput|ConvertTo-Json -Depth 100|ConvertFrom-Json;$lessCertain.fixture_id='ordinary-less-certain';$lessCertain.processes[0].shape_supported=$false;$lessCertain.processes[0].risk.confidence='partial'
$lessCertainIr=New-MIR4ProcessIRV1 -InputRecord $lessCertain -RepoRoot $RepoRoot
if([string]$lessCertainIr.overall_classification-cne'UNKNOWN'){throw '[mir4-w06-uncertainty-monotonicity]'}
$orderA=$records.fixture_irs['scc-order-a'];$orderB=$records.fixture_irs['scc-order-b']
if([string]$orderA.graph_digest-cne[string]$orderB.graph_digest-or(@($orderA.sccs[0].minimal_witness)-join'|')-cne(@($orderB.sccs[0].minimal_witness)-join'|')){throw '[mir4-w06-input-order-invariance]'}

$classes=@($records.effects.channels.class|Sort-Object -Unique)
$expectedClasses=@('MEP-declared scripted channel','MIR runtime operator','compile-time policy','native modifier','opaque','recipe productivity')|Sort-Object
if(($classes-join'|')-cne($expectedClasses-join'|')-or-not$records.effects.opaque_preserved){throw '[mir4-w06-effect-classes]'}
foreach($channel in @($records.effects.channels)){foreach($field in @('subject','value_domain','composition_law','neutral_value','repeatability','saturation','bounds','target_representation','runtime_owner','migration','presentation','proof')){if($null-eq$channel.PSObject.Properties[$field]){throw "[mir4-w06-effect-field] $($channel.id):$field"}};if($channel.package_visible-or-not$channel.semantic_owner_preserved){throw "[mir4-w06-effect-boundary] $($channel.id)"}}
foreach($channel in @($records.effects.channels)){if([string]$channel.owner_ref.sha256-cne(Get-MIR4PlatformInputSha256 (Join-Path $RepoRoot ([string]$channel.owner_ref.path)))){throw "[mir4-w06-owner-canonical-hash] $($channel.id)"}}
$opaque=@($records.effects.channels|Where-Object class -eq opaque)[0]
if($null-ne$opaque.value_domain-or$null-ne$opaque.composition_law-or$null-ne$opaque.bounds-or[string]$opaque.disposition-cne'Preserve'){throw '[mir4-w06-opaque-preservation]'}

$matrix=$records.synthesis
if(@($matrix.constructors|Sort-Object -Unique).Count-ne 10-or@($matrix.terminal_dispositions|Sort-Object -Unique).Count-ne 5-or@($matrix.modes).Count-ne 3-or@($matrix.advanced_ecosystems|Where-Object{$_.status-ne'review-required'-or$_.scope-ne'private-exact-environment-preview'}).Count-ne 0){throw '[mir4-w06-synthesis-matrix]'}
if(@($matrix.candidates|Where-Object{$_.mutation_authorized-or$_.planner_admission-or$_.operation_object}).Count-ne 0-or$matrix.automatic_player_mutation){throw '[mir4-w06-synthesis-boundary]'}
if(@($matrix.candidates|Where-Object assessment -eq 'rejected-hard-safety').Count-lt 1-or@($matrix.candidates|Where-Object assessment -eq 'admissible-preview-proposal-only').Count-lt 1){throw '[mir4-w06-bilateral-candidates]'}
$safe=$records.fixture_irs['ordinary-safe'];$complete=@{'hard-safety'=$true;target=$true;migration=$true;proof=$true}
$completeCandidate=Test-MIR4SynthesisCandidateV1 -ProcessIR $safe -Constructor ContinueSeries -Mode Conservative -ProcessId ([string]$safe.processes[0].identity.id) -Authority $authority -Certificates $complete
if([string]$completeCandidate.assessment-cne'candidate-complete-preview'-or-not$completeCandidate.certificate_gate_complete-or$completeCandidate.mutation_authorized){throw '[mir4-w06-conservative-complete-boundary]'}

$extension=New-MIR4ReferenceExtensionV1 -RepoRoot $RepoRoot
$unavailableLink=Resolve-MIR4W06MepReferences -RepoRoot $RepoRoot -Envelope $extension -ProcessIR $safe -EffectRegistry $records.effects
if(@($unavailableLink.links|Where-Object status -eq unavailable-preserved).Count-ne 2){throw '[mir4-w06-mep-unavailable-link]'}
$linked=$extension|ConvertTo-Json -Depth 100|ConvertFrom-Json
$processFragment=@($linked.fragments|Where-Object kind -eq ProcessClassificationFragment)[0];$effectFragment=@($linked.fragments|Where-Object kind -eq ExternalEffectChannelDeclaration)[0]
$processFragment.data.status='available';$processFragment.data.reason='Synthetic fixture certificate only.';$processFragment.data.certificate_ref='process:'+[string]$safe.processes[0].identity.id+'@'+[string]$safe.processes[0].digest
$channel=$records.effects.channels[0];$effectFragment.data.status='available';$effectFragment.data.channel_ref='channel:'+[string]$channel.id+'@'+[string]$channel.digest;$effectFragment.data.evidence_refs=@('fixture:mir4-process-ir-v1')
$linked.digest='';$linked.digest=Get-MIR4ModuleDigest $linked
$linkResult=Resolve-MIR4W06MepReferences -RepoRoot $RepoRoot -Envelope $linked -ProcessIR $safe -EffectRegistry $records.effects
if(@($linkResult.links|Where-Object status -eq linked).Count-ne 2){throw '[mir4-w06-mep-link]'}
$tampered=$linked|ConvertTo-Json -Depth 100|ConvertFrom-Json;(@($tampered.fragments|Where-Object kind -eq ProcessClassificationFragment)[0]).data.certificate_ref='process:'+[string]$safe.processes[0].identity.id+'@sha256:'+('0'*64);$tampered.digest='';$tampered.digest=Get-MIR4ModuleDigest $tampered
try{Resolve-MIR4W06MepReferences -RepoRoot $RepoRoot -Envelope $tampered -ProcessIR $safe -EffectRegistry $records.effects|Out-Null;throw '[mir4-w06-mep-tamper-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-w06-mep-reference-mismatch]')){throw}}

$sourceText=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/mir/application/processir/ProcessIR.ps1')
if($sourceText-match'(?m)\bdata\.raw\b'-or$sourceText-match'prototypes/mir/(?:planner|emit|runtime).*\.(?:lua|ps1)'){throw '[mir4-w06-forbidden-terminal-import]'}
$output='build/mir4/test-w06-processir-synthesis'
& (Join-Path $RepoRoot 'tools/mir/cli/Export-MIR4ProcessIRSynthesisRecords.ps1') -RepoRoot $RepoRoot -OutputRoot $output|Out-Null
& (Join-Path $RepoRoot 'tools/mir/cli/Export-MIR4ProcessIRSynthesisRecords.ps1') -RepoRoot $RepoRoot -OutputRoot $output -Check|Out-Null
$head=(& git -C $RepoRoot rev-parse HEAD).Trim();$tree=(& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
$schemaByName=@{'MIR4_PROCESSIR_PARITY_RESULT.json'='spec/schemas/mir4-process-ir-v1.schema.json';'MIR4_EFFECT_CHANNEL_REGISTRY.json'='spec/schemas/mir4-effect-channel-registry-v1.schema.json';'MIR4_SYNTHESIS_MATURITY_MATRIX.json'='spec/schemas/mir4-synthesis-maturity-matrix-v1.schema.json'}
foreach($name in $schemaByName.Keys){$path=Join-Path $RepoRoot "$output/$name";$record=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json;if(-not((Get-Content -Raw -LiteralPath $path)|Test-Json -SchemaFile (Join-Path $RepoRoot $schemaByName[$name]))){throw "[mir4-w06-output-schema] $name"};if([string]$record.source_identity.commit-cne$head-or[string]$record.source_identity.tree-cne$tree-or$record.package_visible-or$record.public_release_proof-or$record.player_mutation_authorized){throw "[mir4-w06-output-identity] $name"}}
if((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot)-cne$packageBefore){throw '[mir4-w06-package-mutation]'}
Write-Host '[ok] MIR 4 W06 ProcessIR, effect channels, bilateral safety, and non-mutating synthesis preview passed.'
