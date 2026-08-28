param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/inspection/InspectorCompatibilityMigration.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

function Assert-MIR4InspectorCompatibilityV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$authority=Get-MIR4InspectorCompatibilityAuthority -RepoRoot $repo
foreach($flag in @('semantic_authority','terminal_compatibility_policy_authority','terminal_claim_authority','player_package_mutation_authorized','prototype_write_authorized','runtime_state_mutation_authorized','migration_execution_authorized','planner_or_emitter_admission_authorized','safety_kernel_override_authorized','arbitrary_code_generation_authorized','network_or_upload_authorized','public_support_authorized','signing_or_sealing_authorized','publication_authorized')){Assert-MIR4InspectorCompatibilityV1 (-not[bool]$authority.$flag) 'mir4-inspector-compatibility-authority-firewall' $flag}
$parity=Test-MIR4InspectorCompatibilityFunctionalParityV1 -RepoRoot $repo
Assert-MIR4InspectorCompatibilityV1 ([string]$parity.digest-ceq$script:MIR4InspectorCompatibilityPreCutoverDigestV1) 'mir4-inspector-compatibility-pre-cutover-parity'
Assert-MIR4InspectorCompatibilityV1 (@($parity.record.subjects).Count-eq10-and@($parity.record.sections).Count-eq11-and@($parity.record.canaries).Count-eq8) 'mir4-inspector-compatibility-functional-shape'
Assert-MIR4InspectorCompatibilityV1 (@($parity.record.subjects|Where-Object{$_.id-eq'industrial-revolution-4'-and'BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER'-in@($_.blockers)}).Count-eq1) 'mir4-inspector-compatibility-independent-consumer-blocker'
Assert-MIR4InspectorCompatibilityV1 (@($parity.record.plan|Where-Object{$_.disposition-notin@('Preserve','RequestReview','RequireExtension')}).Count-eq0) 'mir4-inspector-compatibility-safe-dispositions'
$reference=Test-MIR4T13Reference -RepoRoot $repo
Assert-MIR4InspectorCompatibilityV1 ([string]$reference.status-ceq'passed'-and[int]$reference.canary_count-eq8-and[int]$reference.capture_count-eq11-and-not[bool]$reference.package_visible) 'mir4-inspector-compatibility-t13-reference'
Assert-MIR4InspectorCompatibilityV1 ((Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash-ceq$script:MIR4InspectorCompatibilityPolicySha256) 'mir4-inspector-compatibility-policy-read-only'
Assert-MIR4InspectorCompatibilityV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-inspector-compatibility-package-mutation'
[pscustomobject][ordered]@{status='accepted';functional_parity_digest=[string]$parity.digest;subject_count=10;section_count=11;canary_count=8;capture_count=11;package_source_sha256=$packageBefore;package_visible=$false;public_support_authorized=$false;release_transition_authority=$false}
