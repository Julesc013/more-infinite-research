# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'

. (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/inspection/CompatibilityFactory.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
$programmePath=Join-Path $RepoRoot 'spec/programmes/mir4-4x-operating-programme-v1.json'
$programmeText=Get-Content -Raw -LiteralPath $programmePath
if(-not($programmeText|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-4x-operating-programme-v1.schema.json'))){throw '[mir42-a14-programme-schema]'}
$programme=$programmeText|ConvertFrom-Json -Depth 100
$a14=@($programme.synthesis.tasks|Where-Object id -eq 'A14')
$capability=@($programme.synthesis.m44_42_allocation.consumed_by_4_2|Where-Object id -eq 'redacted-support-export')
if($a14.Count-ne1-or'A13'-notin@($a14[0].depends_on)-or'M44-00'-notin@($a14[0].programme_mapping)-or
   $capability.Count-ne1-or[string]$capability[0].task-cne'A14'-or
   [string]$capability[0].evidence.static_test-cne'tests/mir4/Test-MIR42SupportExportA14.ps1'-or
   [string]$capability[0].evidence.candidate_receipt-cne'spec/programmes/evidence/mir42/a14-support-export.json'){
  throw '[mir42-a14-programme-binding]'
}

# This is the package-excluded developer-preview surface.  The candidate-bound
# receipt named by A14 is intentionally future qualification evidence, not a
# synthetic release receipt manufactured by this static contract test.
$references=New-MIR4ReferenceEnvironmentEvidenceV1 -RepoRoot $RepoRoot
$evidence=@(
  [pscustomobject][ordered]@{id='authority.a14';kind='authority';summary='A14 support-export contract authority.';dependencies=@();required_by_reproducer=$false}
  [pscustomobject][ordered]@{id='witness.a14';kind='witness';summary='A14 redacted environment witness.';dependencies=@('authority.a14');required_by_reproducer=$true}
  [pscustomobject][ordered]@{id='context.discardable';kind='context';summary='Non-reproducer context removed by minimization.';dependencies=@();required_by_reproducer=$false}
)
$diagnostics=@(
  [pscustomobject][ordered]@{code='mir42-a14-redaction';severity='error';message='token=MIR42_A14_PRIVATE_TOKEN secret=MIR42_A14_PRIVATE_SECRET path C:\Users\MIR42-A14\profile and /home/mir42-a14/cache'}
)
$bundle=New-MIR4EnvironmentSupportBundleV1 -EnvironmentLock $references.f210 -BundleId 'org.more-infinite-research.a14.support-export-contract' -EvidenceItems $evidence -Diagnostics $diagnostics
Test-MIR4SupportBundleV1 $bundle|Out-Null
if(-not(($bundle|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/preview/mir4-support-bundle-v1.schema.json'))){throw '[mir42-a14-support-schema]'}
if([string]$bundle.target-cne'f210'-or[string]$bundle.maturity-cne'developer-preview'-or-not[bool]$bundle.synthetic-or
   [int]$bundle.redaction.messages_redacted-ne1-or[bool]$bundle.redaction.raw_private_values_retained-or
   ([string]$bundle.diagnostics[0].message)-notmatch'token=<redacted>'-or
   ([string]$bundle.diagnostics[0].message)-notmatch'secret=<redacted>'-or
   ([string]$bundle.diagnostics[0].message)-notmatch'<user-home>'-or
   ([string]$bundle.diagnostics[0].message)-match'MIR42_A14_PRIVATE_(?:TOKEN|SECRET)|[A-Z]:[\\/](?:Users|Documents and Settings)[\\/]|/(?:home|Users)/'){
  throw '[mir42-a14-redaction]'
}
foreach($flag in @('claim_eligible','arbitrary_code','executable_content','network_access_authorized','package_visible','player_mutation_authorized','prototype_write_authorized','public_support_authorized','release_authority')){
  if([bool]$bundle.$flag){throw "[mir42-a14-boundary] $flag"}
}
$minimized=Minimize-MIR4SupportBundleV1 $bundle
Test-MIR4SupportBundleV1 $minimized|Out-Null
if(-not[bool]$minimized.minimized-or[string]$minimized.source_bundle_digest-cne[string]$bundle.digest-or
   ((@($minimized.evidence_items.id|Sort-Object)-join'|')-cne'authority.a14|witness.a14')-or
   [int]$minimized.minimization.removed_evidence_count-ne1){throw '[mir42-a14-minimization]'}

$privateEvidence=@([pscustomobject][ordered]@{id='private.a14';kind='witness';summary='This must not enter a support export.';token='MIR42_A14_PRIVATE_TOKEN';dependencies=@();required_by_reproducer=$true})
try {
  New-MIR4EnvironmentSupportBundleV1 -EnvironmentLock $references.f210 -BundleId 'org.more-infinite-research.a14.private-input' -EvidenceItems $privateEvidence | Out-Null
  throw '[mir42-a14-private-evidence-accepted]'
} catch {
  if(-not$_.Exception.Message.StartsWith('[mir4-environment-private-field]')){throw}
}

$ledger=New-MIR4CompatibilitySubjectLedger -RepoRoot $RepoRoot -SourceIdentity $null
$surface=New-MIR4ReferenceSupportBundleV1 -Ledger $ledger -RepoRoot $RepoRoot -Target f210
Test-MIR4SupportBundleV1 $surface|Out-Null
if(-not(($surface|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/preview/mir4-support-bundle-v1.schema.json'))){throw '[mir42-a14-surface-schema]'}
if([string]$surface.source_ledger_digest-cne[string]$ledger.digest-or@($surface.subjects).Count-lt1-or
   [string]$surface.maturity-cne'developer-preview'-or[bool]$surface.public_support_authorized-or[bool]$surface.release_authority){throw '[mir42-a14-surface-boundary]'}

if((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot)-cne$packageBefore){throw '[mir42-a14-package-mutation]'}
Write-Host '[ok] MIR 4 A14 redacted support-export contract and package-excluded preview surface passed.'
