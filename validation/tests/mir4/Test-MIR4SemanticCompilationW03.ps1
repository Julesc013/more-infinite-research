param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)

$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
$authority=Get-MIR4SemanticCompilerAuthority -RepoRoot $RepoRoot
$providers=@(New-MIR4NormalizedTargetProviders -RepoRoot $RepoRoot)
$runs=@(New-MIR4NormalizedCompilationRuns -RepoRoot $RepoRoot -Providers $providers)
$protocols=New-MIR4ProviderMicroProtocolMatrix -RepoRoot $RepoRoot
$cutover=New-MIR4FeatureSettingCutoverMatrix -RepoRoot $RepoRoot -Providers $providers
$laws=Test-MIR4SemanticMergeLaws -RepoRoot $RepoRoot
if(@($runs).Count-ne 17-or@($runs.target.id|Sort-Object -Unique).Count-ne 17){throw '[mir4-w03-run-count]'}
if(@($runs|Where-Object{[string]$_.kind-ne'MIR4CompilationRunV1'-or[int]$_.schema-ne 1-or$_.authoritative_output-or$_.mutation_capability-or$_.runtime_state_mutation_capability-or$_.public_support_claim}).Count-ne 0){throw '[mir4-w03-run-boundary]'}
if(@($runs|Where-Object{-not$_.contract_set.digest-or-not$_.environment_lock.digest-or-not$_.target_provider.digest-or-not$_.feature_manifest-or-not$_.setting_spec-or-not$_.normalized_facts-or-not$_.graphs-or-not$_.process_ir-or-not$_.policy-or-not$_.claims-or-not$_.resolutions-or@($_.plans).Count-ne 7-or-not$_.operations-or-not$_.runtime_state-or@($_.proof_obligations).Count-lt 6-or-not$_.bounded_public_projections}).Count-ne 0){throw '[mir4-w03-run-incomplete]'}
if(@($runs.plans|Where-Object{$_.executor_authorized}).Count-ne 0){throw '[mir4-w03-executor-authority]'}
if(@($protocols.protocols).Count-ne 13-or@($protocols.protocols|Where-Object{$_.rewrite_required-or'mutate-prototype'-notin@($_.forbidden_operations)}).Count-ne 0){throw '[mir4-w03-protocol-adapter]'}
if(@($cutover.targets).Count-ne 17-or@($cutover.targets|Where-Object{-not$_.feature_manifest.aggregate_only-or-not$_.setting_spec.aggregate_only-or$_.duplicated_fact_or_policy_authority-or$_.package_visible}).Count-ne 0){throw '[mir4-w03-feature-setting-cutover]'}
if(-not$laws.implemented_passed-or@($laws.laws|Where-Object{$_.passed}).Count-ne 12-or@($laws.deferred_owners).Count-ne 0-or-not$laws.complete){throw '[mir4-w03-merge-laws]'}
if(@($authority.terminal_player_authority|Where-Object{-not(Test-Path -LiteralPath (Join-Path $RepoRoot ([string]$_)) -PathType Leaf)}).Count-ne 0){throw '[mir4-w03-terminal-authority]'}
$output='build/mir4/test-w03-semantic-compiler'
& (Join-Path $RepoRoot 'tools/commands/mir4/Export-MIR4SemanticCompilerRecords.ps1') -RepoRoot $RepoRoot -OutputRoot $output|Out-Null
& (Join-Path $RepoRoot 'tools/commands/mir4/Export-MIR4SemanticCompilerRecords.ps1') -RepoRoot $RepoRoot -OutputRoot $output -Check|Out-Null
$head=(& git -C $RepoRoot rev-parse HEAD).Trim();$tree=(& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
foreach($name in @('MIR4_COMPILATION_RUN_CONTRACT.json','MIR4_FEATURE_SETTING_CUTOVER_MATRIX.json','MIR4_PROVIDER_MICRO_PROTOCOL_MATRIX.json','MIR4_MERGE_LAW_CATALOGUE.json')){$record=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$output/$name")|ConvertFrom-Json;if([string]$record.source_identity.commit-cne$head-or[string]$record.source_identity.tree-cne$tree-or$record.package_visible-or$record.public_release_proof){throw "[mir4-w03-export-identity] $name"}}
if((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot)-cne$packageBefore){throw '[mir4-w03-package-mutation]'}
Write-Host '[ok] MIR 4 W03 semantic CompilationRun V1, protocol adapters, and merge laws passed.'
