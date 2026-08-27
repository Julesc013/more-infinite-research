param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

function Assert-MIR4SemanticCompilerV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$compatibilityBefore=(Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash
$providers=@(New-MIR4NormalizedTargetProviders -RepoRoot $repo)
$runs=@(New-MIR4NormalizedCompilationRuns -RepoRoot $repo -Providers $providers)
$protocols=New-MIR4ProviderMicroProtocolMatrix -RepoRoot $repo
$cutover=New-MIR4FeatureSettingCutoverMatrix -RepoRoot $repo -Providers $providers
$laws=Test-MIR4SemanticMergeLaws -RepoRoot $repo

Assert-MIR4SemanticCompilerV1 ($providers.Count-eq17-and$runs.Count-eq17) 'mir4-semantic-compiler-target-run-count'
Assert-MIR4SemanticCompilerV1 (@($runs|Where-Object{$_.authoritative_output-or$_.mutation_capability-or$_.runtime_state_mutation_capability-or$_.public_support_claim}).Count-eq0) 'mir4-semantic-compiler-authority-firewall'
Assert-MIR4SemanticCompilerV1 (@($protocols.protocols).Count-eq13-and@($protocols.protocols|Where-Object{$_.rewrite_required}).Count-eq0) 'mir4-semantic-compiler-protocols'
Assert-MIR4SemanticCompilerV1 (@($cutover.targets).Count-eq17-and@($cutover.targets|Where-Object{$_.duplicated_fact_or_policy_authority-or$_.package_visible}).Count-eq0) 'mir4-semantic-compiler-cutover'
Assert-MIR4SemanticCompilerV1 ([bool]$laws.complete-and[bool]$laws.implemented_passed-and@($laws.laws).Count-eq12-and@($laws.laws|Where-Object{-not$_.passed}).Count-eq0) 'mir4-semantic-compiler-laws'

$safe=[pscustomobject][ordered]@{subject='safe';operations=@('data-only-fragment');evidence=@('fixture:safe');requested_disposition='preserve';positive_cycle=$false;proven_bounded=$true;owner_opaque=$false;owner_rewrite=$false}
$unsafe=[pscustomobject][ordered]@{subject='unsafe';operations=@('prototype-write');evidence=@('fixture:unsafe');requested_disposition='handle';positive_cycle=$false;proven_bounded=$true;owner_opaque=$false;owner_rewrite=$false}
$safeDecision=Resolve-MIR4PolicyDisposition -Contribution $safe
$unsafeDecision=Resolve-MIR4PolicyDisposition -Contribution $unsafe
Assert-MIR4SemanticCompilerV1 ([string]$safeDecision.disposition-ceq'preserve'-and-not[bool]$safeDecision.mutation_authorized) 'mir4-semantic-policy-safe-disposition'
Assert-MIR4SemanticCompilerV1 ([string]$unsafeDecision.disposition-ceq'fail-hard-safety'-and[string]$unsafeDecision.safety.status-ceq'rejected'-and-not[bool]$unsafeDecision.safety.hard_safety_overridable) 'mir4-semantic-policy-hard-safety'

$canonicalOutput='build/mir4/test-semantic-compiler-canonical'
$compatibilityOutput='build/mir4/test-semantic-compiler-compatibility'
& (Join-Path $repo 'tools/mir/cli/Export-MIR4SemanticCompilerRecords.ps1') -RepoRoot $repo -OutputRoot $canonicalOutput|Out-Null
& (Join-Path $repo 'tools/commands/mir4/Export-MIR4SemanticCompilerRecords.ps1') -RepoRoot $repo -OutputRoot $compatibilityOutput|Out-Null
$names=@('MIR4_COMPILATION_RUN_CONTRACT.json','MIR4_FEATURE_SETTING_CUTOVER_MATRIX.json','MIR4_PROVIDER_MICRO_PROTOCOL_MATRIX.json','MIR4_MERGE_LAW_CATALOGUE.json')
foreach($name in $names){
  $canonical=(Get-FileHash -LiteralPath (Join-Path $repo "$canonicalOutput/$name") -Algorithm SHA256).Hash
  $compatibility=(Get-FileHash -LiteralPath (Join-Path $repo "$compatibilityOutput/$name") -Algorithm SHA256).Hash
  Assert-MIR4SemanticCompilerV1 ($canonical-ceq$compatibility) 'mir4-semantic-compiler-command-parity' $name
}
& (Join-Path $repo 'tools/mir/cli/Export-MIR4SemanticCompilerRecords.ps1') -RepoRoot $repo -OutputRoot $canonicalOutput -Check|Out-Null
& (Join-Path $repo 'tools/commands/mir4/Export-MIR4SemanticCompilerRecords.ps1') -RepoRoot $repo -OutputRoot $compatibilityOutput -Check|Out-Null

$packageFiles=@(Get-MIRPackageSourceFiles -RepoRoot $repo)
foreach($path in @('tools/mir/domain/safety/SafetyKernel.ps1','tools/mir/domain/policy/PolicyEngine.ps1','tools/mir/application/compiler/NormalizedCompiler.ps1','tools/mir/application/compiler/CompilationRun.ps1','tools/mir/cli/Export-MIR4SemanticCompilerRecords.ps1','tests/compiler/Test-MIR4SemanticCompiler.ps1')){
  Assert-MIR4SemanticCompilerV1 ($path-notin$packageFiles) 'mir4-semantic-compiler-package-visible' $path
}
Assert-MIR4SemanticCompilerV1 ((Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash-ceq$compatibilityBefore) 'mir4-semantic-compiler-compatibility-policy-mutation'
Assert-MIR4SemanticCompilerV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-semantic-compiler-package-source-mutation'

[pscustomobject][ordered]@{status='passed';canonical_application='tools/mir/application/compiler/CompilationRun.ps1';canonical_policy='tools/mir/domain/policy/PolicyEngine.ps1';target_count=$providers.Count;merge_law_count=@($laws.laws).Count;package_source_sha256=$packageBefore;release_transition_authority=$false}
