param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/inspection/Inspector.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/inspection/CompatibilityFactory.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
$authorityText=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Inspector-Compatibility-ProgrammeV1.json')
if(-not($authorityText|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-inspector-compatibility-programme-v1.schema.json'))){throw '[mir4-w07-authority-schema]'}
$authority=Get-MIR4InspectorCompatibilityAuthority -RepoRoot $RepoRoot
if(@($authority.inspector_sections).Count-ne 11-or@($authority.named_ecosystems).Count-ne 10-or@($authority.safe_choice_priority).Count-ne 7-or@($authority.factory_pipeline).Count-ne 7-or@($authority.factory_zip_allowlist).Count-ne 9){throw '[mir4-w07-authority-counts]'}
if([bool]$authority.tooling.package_visible-or[bool]$authority.tooling.release_transition_authority-or[string]$authority.tooling.migration_authority-cne'governance/repository/migrations/inspector-compatibility-tooling-v1.json'){throw '[mir4-w07-tooling-authority]'}
foreach($flag in @('semantic_authority','terminal_compatibility_policy_authority','terminal_claim_authority','player_package_mutation_authorized','prototype_write_authorized','runtime_state_mutation_authorized','migration_execution_authorized','planner_or_emitter_admission_authorized','safety_kernel_override_authorized','arbitrary_code_generation_authorized','network_or_upload_authorized','public_support_authorized','signing_or_sealing_authorized','publication_authorized')){if([bool]$authority.$flag){throw "[mir4-w07-authority-boundary] $flag"}}

$ledger=New-MIR4CompatibilitySubjectLedger -RepoRoot $RepoRoot -SourceIdentity $null
Test-MIR4CompatibilitySubjectLedger -Ledger $ledger -RepoRoot $RepoRoot|Out-Null
if(-not(($ledger|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-compatibility-subject-ledger-v1.schema.json'))){throw '[mir4-w07-ledger-schema]'}
$expectedIds=@('aai','angel','base-and-official','bob','bz','industrial-revolution-3','industrial-revolution-4','k2-k2so','pyanodons','space-exploration')
if((@($ledger.subjects.subject_id|Sort-Object)-join'|')-cne($expectedIds-join'|')-or@($ledger.target_dispositions).Count-ne 17){throw '[mir4-w07-subject-target-set]'}
foreach($subject in @($ledger.subjects)){if($subject.claim.eligible-or$subject.claim.public_authorized-or$subject.claim.blanket-or$subject.proof.public_release_proof-or$subject.implementation.automatic_mutation-or$subject.target_portability.cross_target_transfer_authorized){throw "[mir4-w07-subject-boundary] $($subject.subject_id)"}}
$aai=@($ledger.subjects|Where-Object subject_id -eq aai)[0]
if([string]$aai.proof.state-cne'historical-development-evidence-nontransferable'-or@($aai.proof.evidence|Where-Object{$_.status-ne'historical-development-evidence-nontransferable'-or$_.claim_eligible}).Count){throw '[mir4-w07-historical-evidence-transfer]'}
$ir4=@($ledger.subjects|Where-Object subject_id -eq industrial-revolution-4)[0]
if([string]$ir4.proof.state-cne'review-required/no-governed-exact-archive-closure'-or'BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER'-notin@($ir4.blockers)){throw '[mir4-w07-ir4-blocker]'}
if($ledger.PSObject.Properties.Name-match'(?i)^modpack[_-]?supported$'){throw '[mir4-w07-blanket-support-property]'}

$page1=Get-MIR4CompatibilityPage -Ledger $ledger -RepoRoot $RepoRoot -Limit 3
$page2=Get-MIR4CompatibilityPage -Ledger $ledger -RepoRoot $RepoRoot -Limit 3 -Cursor $page1.page.next_cursor
$page1Repeat=Get-MIR4CompatibilityPage -Ledger $ledger -RepoRoot $RepoRoot -Limit 3
if($page1.digest-cne$page1Repeat.digest-or$page1.page.returned-ne 3-or$page1.page.next_cursor-cne'3'-or@($page1.items.subject_id|Where-Object{$_-in@($page2.items.subject_id)}).Count){throw '[mir4-w07-pagination-determinism]'}
$f200=Get-MIR4CompatibilityPage -Ledger $ledger -RepoRoot $RepoRoot -Target f200
if($f200.page.total-ne 1-or[string]$f200.items[0].subject_id-cne'k2-k2so'){throw '[mir4-w07-target-filter]'}
foreach($request in @(@{Limit=51;Cursor='0';Expected='[mir4-w07-page-limit]'},@{Limit=3;Cursor='bad';Expected='[mir4-w07-page-cursor]'})){try{Get-MIR4CompatibilityPage -Ledger $ledger -RepoRoot $RepoRoot -Limit $request.Limit -Cursor $request.Cursor|Out-Null;throw '[mir4-w07-invalid-page-accepted]'}catch{if(-not$_.Exception.Message.StartsWith($request.Expected)){throw}}}

foreach($name in @('negative/blanket-support-boolean.json','negative/forbidden-callback.json')){
  $bad=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures/mir4-inspector-compatibility-v1/$name")|ConvertFrom-Json -Depth 100
  try{New-MIR4SupportBundleV1 -Request $bad -Ledger $ledger -RepoRoot $RepoRoot|Out-Null;throw "[mir4-w07-negative-accepted] $name"}catch{if(-not$_.Exception.Message.StartsWith('[mir4-w07-forbidden-field]')){throw}}
}
$unbounded=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-inspector-compatibility-v1/negative/unbounded-page.json')|ConvertFrom-Json
try{Get-MIR4CompatibilityPage -Ledger $ledger -RepoRoot $RepoRoot -Limit ([int]$unbounded.limit) -Cursor ([string]$unbounded.cursor)|Out-Null;throw '[mir4-w07-unbounded-page-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-w07-page-limit]')){throw}}

$syntheticExpectation=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-inspector-compatibility-v1/evidence/synthetic-claim-attempt.json')|ConvertFrom-Json
if([string]$syntheticExpectation.evidence_status-cne[string]$authority.evidence_statuses.synthetic-or$syntheticExpectation.expected_claim_eligible){throw '[mir4-w07-synthetic-claim-boundary]'}
$ir4Expectation=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-inspector-compatibility-v1/evidence/ir4-no-exact-closure.json')|ConvertFrom-Json
if([string]$ir4Expectation.expected_status-cne[string]$ir4.proof.state-or[string]$ir4Expectation.expected_blocker-notin@($ir4.blockers)){throw '[mir4-w07-ir4-evidence-fixture]'}
$provenance=Test-MIR4CompatibilityProvenance -Ledger $ledger -RepoRoot $RepoRoot
if([string]$provenance.status-cne'current'-or@($provenance.rows|Where-Object status -ne current).Count){throw '[mir4-w07-provenance-current]'}
$stale=$ledger|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$stale.input_digests.sol07='0'*64
if([string](Test-MIR4CompatibilityProvenance -Ledger $stale -RepoRoot $RepoRoot).status-cne'stale'){throw '[mir4-w07-provenance-stale]'}

$bounded=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-inspector-compatibility-v1/positive/bounded-reference-request.json')|ConvertFrom-Json -Depth 100
$support=New-MIR4SupportBundleV1 -Request $bounded -Ledger $ledger -RepoRoot $RepoRoot
$plan=New-MIR4CompatibilityFactoryPlanV1 -SupportBundle $support -Ledger $ledger -RepoRoot $RepoRoot -SourceIdentity $null
Test-MIR4CompatibilityFactoryPlanV1 -Plan $plan -RepoRoot $RepoRoot|Out-Null
if(@($plan.plans).Count-ne 3-or@($plan.priority).Count-ne 7-or$plan.package_visible-or$plan.public_release_proof-or$plan.player_mutation_authorized-or-not(($plan|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-compatibility-factory-plan-v1.schema.json'))){throw '[mir4-w07-plan-boundary]'}
foreach($row in @($plan.plans)){if(@($row.choice_path|Where-Object state -eq rejected-with-reason|Where-Object{[string]::IsNullOrWhiteSpace([string]$_.reason)}).Count-or@($row.executable_operations).Count-or$row.claim_eligible-or$row.automatic_mutation){throw "[mir4-w07-choice-path] $($row.subject_id)"}}
$orderA=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-inspector-compatibility-v1/permutation/subject-order-a.json')|ConvertFrom-Json -Depth 100
$orderB=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-inspector-compatibility-v1/permutation/subject-order-b.json')|ConvertFrom-Json -Depth 100
$supportA=New-MIR4SupportBundleV1 -Request $orderA -Ledger $ledger -RepoRoot $RepoRoot;$supportB=New-MIR4SupportBundleV1 -Request $orderB -Ledger $ledger -RepoRoot $RepoRoot
$planA=New-MIR4CompatibilityFactoryPlanV1 -SupportBundle $supportA -Ledger $ledger -RepoRoot $RepoRoot -SourceIdentity $null;$planB=New-MIR4CompatibilityFactoryPlanV1 -SupportBundle $supportB -Ledger $ledger -RepoRoot $RepoRoot -SourceIdentity $null
if($supportA.digest-cne$supportB.digest-or$planA.digest-cne$planB.digest){throw '[mir4-w07-factory-order-invariance]'}

$outRoot='build/mir4/test-w07-inspector-compatibility'
$zipA=Export-MIR4CompatibilityFactoryDataBundleV1 -RepoRoot $RepoRoot -SupportBundle $support -Ledger $ledger -Plan $plan -OutputPath "$outRoot/factory-a.zip"
$zipB=Export-MIR4CompatibilityFactoryDataBundleV1 -RepoRoot $RepoRoot -SupportBundle $support -Ledger $ledger -Plan $plan -OutputPath "$outRoot/factory-b.zip"
if($zipA.sha256-cne$zipB.sha256-or$zipA.entry_count-ne 9-or$zipA.status-cne'passed-data-only-package-excluded'){throw '[mir4-w07-factory-zip-determinism]'}
$zipCheck=Test-MIR4CompatibilityFactoryDataBundleV1 -RepoRoot $RepoRoot -ZipPath $zipA.path
if($zipCheck.entry_count-ne 9-or-not$zipCheck.allowlist_exact-or$zipCheck.executable_entries-ne 0){throw '[mir4-w07-factory-zip-boundary]'}

$workbench=New-MIR4InspectorWorkbenchResultV1 -RepoRoot $RepoRoot -Ledger $ledger -FactoryPlan $plan -FactoryPackage $zipA -SourceIdentity $null
Test-MIR4InspectionBundleV1 -Bundle $workbench.inspection_bundle -RepoRoot $RepoRoot|Out-Null
Test-MIR4InspectorHtmlV1 -Html $workbench.html|Out-Null
if(@($workbench.inspection_bundle.sections).Count-ne 11-or$workbench.inspection_bundle.network_or_upload_authorized-or$workbench.inspection_bundle.idle_runtime_work-or$workbench.result.offline.network_calls-ne 0-or$workbench.result.offline.upload_paths-ne 0-or[string]$workbench.result.blockers.process_ir-cne'CAPTURED-EXACT-TARGET-PROCESSIR-PREVIEW'){throw '[mir4-w07-workbench-boundary]'}
foreach($check in @(@{Value=$workbench.inspection_bundle;Schema='spec/schemas/mir4-inspection-bundle-v1.schema.json'},@{Value=$workbench.result;Schema='spec/schemas/mir4-inspector-workbench-result-v1.schema.json'})){if(-not(($check.Value|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot $check.Schema))){throw "[mir4-w07-output-schema] $($check.Schema)"}}

$processIr=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'sdk/preview/mir4/reference/process-ir-parity-result.json')|ConvertFrom-Json -Depth 100
if([string]$processIr.exact_target_status-cne'CAPTURED-EXACT-F210-F200-PROCESSIR-PREVIEW-WITH-DECLARED-CUSTODY-BLOCKER'-or-not$processIr.exact_target_evidence.deterministic-or$processIr.exact_target_evidence.authoritative-or$processIr.public_release_proof-or-not[string]::IsNullOrWhiteSpace([string]$processIr.source_identity.commit)-or-not[string]::IsNullOrWhiteSpace([string]$processIr.source_identity.tree)){throw '[mir4-w07-processir-claim-gate]'}
foreach($source in @('tools/mir/application/inspection/CompatibilityIndex.ps1','tools/mir/application/inspection/SupportAssessment.ps1','tools/mir/application/inspection/Inspector.ps1','tools/mir/application/inspection/CompatibilityFactory.ps1')){$text=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $source);if($text-match'(?m)\bdata\.raw\b'-or$text-match'prototypes/mir/(?:planner|emit|runtime)'){throw "[mir4-w07-forbidden-terminal-import] $source"}}

Invoke-MIR4PlatformGenerate -RepoRoot $RepoRoot -Check|Out-Null
Test-MIR4PlatformConformance -RepoRoot $RepoRoot|Out-Null
$recordsOut='build/mir4/m4c02-inspector-compatibility'
& (Join-Path $RepoRoot 'tools/mir/cli/Export-MIR4InspectorCompatibilityRecords.ps1') -RepoRoot $RepoRoot -OutputRoot $recordsOut|Out-Null
& (Join-Path $RepoRoot 'tools/mir/cli/Export-MIR4InspectorCompatibilityRecords.ps1') -RepoRoot $RepoRoot -OutputRoot $recordsOut -Check|Out-Null
foreach($name in @('MIR4_INSPECTOR_WORKBENCH_RESULT.json','MIR4_COMPATIBILITY_SUBJECT_LEDGER.json')){$record=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$recordsOut/$name")|ConvertFrom-Json -Depth 100;if($record.package_visible-or$record.public_release_proof-or$record.player_mutation_authorized){throw "[mir4-w07-record-boundary] $name"}}
if((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot)-cne$packageBefore){throw '[mir4-w07-package-mutation]'}
Write-Host '[ok] MIR 4 W07 bounded Inspector, normalized evidence, and data-only compatibility factory passed.'
