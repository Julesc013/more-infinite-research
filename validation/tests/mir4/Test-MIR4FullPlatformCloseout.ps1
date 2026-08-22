param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/FullPlatformCloseout.ps1')

$source=[pscustomobject][ordered]@{programme_id='M4C02-09-24H';commit=('a'*40);tree=('b'*40);source_version='4.0.0';package_source_sha256=('C'*64)}
$evidence=@([pscustomobject][ordered]@{path='evidence.json';sha256=('D'*64);role='test-evidence'})
$record=New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4FullPlatformTestV1' -Status 'passed' -Maturity shadow -AuthorityId test-authority -AuthorityMode evidence-only-aggregation -AuthoritySourcePaths @('authority.json') -EvidenceRefs $evidence -Payload ([ordered]@{value=1})
$schema=Join-Path $repo 'spec/schemas/mir4-full-platform-record-v1.schema.json'
if(-not(($record|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile $schema)-or-not(Test-MIR4BootstrapRecordHash -Record $record)){throw '[mir4-full-platform-record-contract]'}
$repeat=New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4FullPlatformTestV1' -Status 'passed' -Maturity shadow -AuthorityId test-authority -AuthorityMode evidence-only-aggregation -AuthoritySourcePaths @('authority.json') -EvidenceRefs $evidence -Payload ([ordered]@{value=1})
if([string]$record.record_sha256-cne[string]$repeat.record_sha256){throw '[mir4-full-platform-record-nondeterministic]'}
$record.payload.value=2
if(Test-MIR4BootstrapRecordHash -Record $record){throw '[mir4-full-platform-record-tamper-admitted]'}
$record.payload.value=1
$record.package_visible=$true
if(($record|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue){throw '[mir4-full-platform-package-visible-admitted]'}

$audit=[pscustomobject][ordered]@{schema=1;kind='MIR4LunaAuditInputV1';programme_id='M4C02-09-24H';auditor_model='gpt-5.6-luna';audit_scope=[ordered]@{commit=$source.commit;tree=$source.tree};decision='ACCEPT';b0_findings=@();b1_findings=@();merge_recommendation='APPROVE';evidence_refs=$evidence}
$auditSchema=Join-Path $repo 'spec/schemas/mir4-luna-audit-input-v1.schema.json'
if(-not(($audit|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile $auditSchema)-or-not(Test-MIR4FullPlatformAuditInput -Audit $audit -SourceIdentity $source)){throw '[mir4-full-platform-audit-contract]'}
$audit.audit_scope.tree='c'*40
if(Test-MIR4FullPlatformAuditInput -Audit $audit -SourceIdentity $source){throw '[mir4-full-platform-stale-audit-admitted]'}
$audit.audit_scope.tree=$source.tree;$audit.b0_findings=@('B0 defect')
if(Test-MIR4FullPlatformAuditInput -Audit $audit -SourceIdentity $source){throw '[mir4-full-platform-b0-acceptance-admitted]'}

$blockers=@(Get-MIR4FullPlatformBlockers)
$requiredBlockers=@('BLOCKED-HUMAN-SECRET-INPUT','BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER','BLOCKED-EXACT-TARGET-PROCESSIR-SNAPSHOT','BLOCKED-MISSING-EXACT-ENGINE-f018','BLOCKED-MISSING-TRUSTED-TIMING-CAPACITY-EVIDENCE','BLOCKED-MUSEUM-RIGHTS-CUSTODY-RESTORE-CLOSURE','BLOCKED-FUTURE-INDEPENDENT-PRODUCTION-HOST')
if($blockers.Count-ne$requiredBlockers.Count-or@($requiredBlockers|Where-Object{$_-notin@($blockers.id)}).Count){throw '[mir4-full-platform-blocker-loss]'}
if(@($blockers|Where-Object{$_.workaround_permitted}).Count){throw '[mir4-full-platform-blocker-workaround-admitted]'}

$exporter=Join-Path $repo 'tools/commands/mir4/Export-MIR4FullPlatform24HRecords.ps1'
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseFile($exporter,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw "[mir4-full-platform-exporter-parse] $($errors.Message -join '; ')"}
$text=Get-Content -Raw -LiteralPath $exporter
$requiredOutputs=@(
  'MIR4_RELEASE_GOVERNANCE_READINESS.json','MIR4_SIGNING_AUTHORITY_PUBLIC.json','MIR4_ALLOWED_SIGNERS','MIR4_KEY_RECOVERY_TEST.json','MIR4_LEDGER_INITIALIZATION.json','MIR4_PUBLISHER_CONFINEMENT.json',
  'MIR4_AUTHORITY_MAP_FINAL.json','MIR4_REPOSITORY_FIXED_POINT.json','MIR4_PATH_MIGRATION_MATRIX.json','MIR4_SHIM_DEBT_REGISTER.json',
  'MIR4_TARGET_PROVIDER_MATRIX.json','MIR4_TARGET_DISPOSITION_MATRIX.json','MIR4_PRIVATE_PACKAGE_MATRIX.json',
  'MIR4_COMPILATION_RUN_CONTRACT.json','MIR4_FEATURE_SETTING_CUTOVER_MATRIX.json','MIR4_PROVIDER_MICRO_PROTOCOL_MATRIX.json','MIR4_MERGE_LAW_CATALOGUE.json',
  'MIR4_RUNTIME_STATE_MATRIX.json','MIR4_MIGRATION_GRAPH_MATRIX.json','MIR4_CONTINUITY_BUNDLE.json',
  'MIR4_MEP_CONFORMANCE.json','MIR4_API_SDK_GRADUATION_MATRIX.json','MIR4_REFERENCE_CONSUMER_RESULT.json',
  'MIR4_PROCESSIR_PARITY_RESULT.json','MIR4_EFFECT_CHANNEL_REGISTRY.json','MIR4_SYNTHESIS_MATURITY_MATRIX.json',
  'MIR4_INSPECTOR_WORKBENCH_RESULT.json','MIR4_COMPATIBILITY_SUBJECT_LEDGER.json',
  'MIR4_ASSURANCE_SCALE_RESULT.json','MIR4_RELEASE_BUDGET_PLAN.json','MIR4_OFFLINE_DRILL_RESULT.json',
  'MIR4_HISTORICAL_MUSEUM_MATRIX.json','MIR4_SUCCESSOR_HOST_RESULT.json',
  'MIR4_FULL_PLATFORM_24H_COMPLETION_RECORD.json','MIR4_FULL_PLATFORM_24H_BLOCKER_MATRIX.json','MIR4_FULL_PLATFORM_24H_LUNA_ACCEPTANCE.json','MIR4_FULL_PLATFORM_24H_DEV_MERGE_RECEIPT.json','MIR4_SOURCE_FREEZE_READINESS_FINAL.json','SHA256SUMS.json'
)
if($requiredOutputs.Count-ne39-or@($requiredOutputs|Sort-Object -Unique).Count-ne39-or@($requiredOutputs|Where-Object{$text-notmatch[regex]::Escape($_)}).Count){throw '[mir4-full-platform-required-output-loss]'}
foreach($forbidden in @('git push','gh pr create','git tag','source freeze','production seal')){if($text-match[regex]::Escape($forbidden)){throw "[mir4-full-platform-mutation-command] $forbidden"}}
foreach($path in @('spec/schemas/mir4-full-platform-record-v1.schema.json','spec/schemas/mir4-luna-audit-input-v1.schema.json','tools/lib/mir4/FullPlatformCloseout.ps1','tools/commands/mir4/Export-MIR4FullPlatform24HRecords.ps1','docs/maintainer/mir4-full-platform-closeout.md')){if(-not(Test-Path -LiteralPath (Join-Path $repo $path)-PathType Leaf)){throw "[mir4-full-platform-path-missing] $path"}}

Write-Host '[ok] MIR 4 full-platform evidence-only closeout schemas, blocker preservation, audit binding, and 39-record inventory passed.'
