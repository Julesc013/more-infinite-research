param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'

. (Join-Path $RepoRoot 'tools/mir/application/assurance/EnvironmentEvidence.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PackagePresentation.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')

$before=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
Assert-MIR4PackagePresentationV1 -RepoRoot $RepoRoot -PackageSourceSha256 $before|Out-Null

$a=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-environment-evidence-v1/positive/environment-f210-a.json')|ConvertFrom-Json -Depth 100
$b=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-environment-evidence-v1/positive/environment-f210-b.json')|ConvertFrom-Json -Depth 100
$lockA=New-MIR4EnvironmentLockV1 $a
$lockB=New-MIR4EnvironmentLockV1 $b
if([string]$lockA.digest-cne[string]$lockB.digest){throw '[mir4-t10-permutation-digest]'}
Test-MIR4EnvironmentLockV1 $lockA|Out-Null
if(-not(($lockA|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/preview/mir4-environment-lock-v1.schema.json'))){throw '[mir4-t10-lock-schema]'}

$same=New-MIR4EnvironmentDiffV1 -Base $lockA -Candidate $lockB
if([string]$same.status-cne'identical'-or[int]$same.change_count-ne0){throw '[mir4-t10-identical-diff]'}
$references=New-MIR4ReferenceEnvironmentEvidenceV1 -RepoRoot $RepoRoot
if([string]$references.diff.status-cne'changed'-or-not[bool]$references.diff.summary.identity_changed){throw '[mir4-t10-exact-target-diff]'}
if(-not(($references.diff|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/preview/mir4-environment-diff-v1.schema.json'))){throw '[mir4-t10-diff-schema]'}

$private=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-environment-evidence-v1/negative/private-token.json')|ConvertFrom-Json -Depth 100
try{New-MIR4EnvironmentLockV1 $private|Out-Null;throw '[mir4-t10-private-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-environment-private-field]')){throw}}
$privatePath=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-environment-evidence-v1/negative/private-path.json')|ConvertFrom-Json -Depth 100
try{New-MIR4EnvironmentLockV1 $privatePath|Out-Null;throw '[mir4-t10-private-path-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-environment-private-value]')){throw}}
$extensionManifest=$a|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
$extensionManifest.extensions=@([pscustomobject][ordered]@{extension_id='org.example.reference';version='1.0.0';digest=('C'*64)})
$extensionLock=New-MIR4EnvironmentLockV1 $extensionManifest
if([string]$extensionLock.extensions[0].digest-cne('sha256:'+('c'*64))){throw '[mir4-t10-extension-digest]'}

$evidence=@(
  [pscustomobject][ordered]@{id='source.root';kind='authority';summary='Root authority';dependencies=@();required_by_reproducer=$false}
  [pscustomobject][ordered]@{id='witness.required';kind='witness';summary='Required witness';dependencies=@('source.root');required_by_reproducer=$true}
  [pscustomobject][ordered]@{id='context.remove';kind='context';summary='Unrelated context';dependencies=@();required_by_reproducer=$false}
)
$bundle=New-MIR4EnvironmentSupportBundleV1 -EnvironmentLock $lockA -EvidenceItems $evidence -Diagnostics @(
  [pscustomobject][ordered]@{code='mir4-test-path';severity='error';message='Failure at C:\Users\Alice\mods token=super-secret password=hunter2'}
)
if((ConvertTo-MIR4CanonicalJsonV1 $bundle)-match'Alice|super-secret|hunter2'){throw '[mir4-t10-redaction-leak]'}
$minimized=Minimize-MIR4SupportBundleV1 $bundle
if(@($minimized.evidence_items).Count-ne2-or[int]$minimized.minimization.removed_evidence_count-ne1-or
   [string]$minimized.reproducer.signature-cne[string]$bundle.reproducer.signature){throw '[mir4-t10-minimizer-reproducer]'}
if(@($minimized.evidence_items|Where-Object { [string]$_.id -ceq 'source.root' }).Count-ne1){throw '[mir4-t10-minimizer-transitive-closure]'}
Test-MIR4SupportBundleV1 $minimized|Out-Null
if(-not(($minimized|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/preview/mir4-support-bundle-v1.schema.json'))){throw '[mir4-t10-support-schema]'}

$tampered=$minimized|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
$tampered.environment_lock.target='f200'
try{Test-MIR4SupportBundleV1 $tampered|Out-Null;throw '[mir4-t10-tamper-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-environment-lock-digest]')){throw}}

foreach($value in @($references.f210,$references.f200,$references.diff,$references.bundle,$references.minimized)){
  foreach($flag in @('package_visible','player_mutation_authorized','prototype_write_authorized','public_support_authorized','release_authority')){
    if($null-ne$value.PSObject.Properties[$flag]-and[bool]$value.$flag){throw "[mir4-t10-authority] $($value.kind).$flag"}
  }
}

$cliOutput=Join-Path $RepoRoot 'build/mir4/t10/environment-reference.json'
& (Join-Path $RepoRoot 'tools/mir/cli/Invoke-MIR4EnvironmentEvidence.ps1') reference -RepoRoot $RepoRoot -OutputPath $cliOutput
if(-not(Test-Path -LiteralPath $cliOutput -PathType Leaf)){throw '[mir4-t10-cli-output]'}

$shipped=@(Get-MIRPackageSourceFiles -RepoRoot $RepoRoot)
foreach($path in @(
  'tools/mir/application/assurance/EnvironmentEvidence.ps1','tools/mir/cli/Invoke-MIR4EnvironmentEvidence.ps1',
  'docs/reference/mir4-environment-evidence.md','fixtures/mir4-environment-evidence-v1',
  'spec/schemas/preview/mir4-environment-lock-v1.schema.json','spec/schemas/preview/mir4-environment-diff-v1.schema.json',
  'spec/schemas/preview/mir4-support-bundle-v1.schema.json'
)){
  if(@($shipped|Where-Object{$_-eq$path-or$_.StartsWith($path+'/')}).Count){throw "[mir4-t10-package-visible] $path"}
}
$after=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
if($after-cne$before){throw '[mir4-t10-package-mutation]'}
Write-Host '[ok] MIR 4 T10 environment lock, diff, redacted support bundle, and reproducer-preserving minimizer passed.'
