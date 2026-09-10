# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'

. (Join-Path $RepoRoot 'tools/mir/application/assurance/EnvironmentEvidence.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PackagePresentation.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')

$before=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
Assert-MIR4CurrentPackagePresentationV2 -RepoRoot $RepoRoot -PackageSourceSha256 $before|Out-Null

$a=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-environment-evidence-v1/positive/environment-f210-a.json')|ConvertFrom-Json -Depth 100
$b=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-environment-evidence-v1/positive/environment-f210-b.json')|ConvertFrom-Json -Depth 100
$lockA=New-MIR4EnvironmentLockV1 $a
$lockB=New-MIR4EnvironmentLockV1 $b
if([string]$lockA.digest-cne[string]$lockB.digest){throw '[mir4-t10-permutation-digest]'}
if([string]$lockA.digest-cne'sha256:4343c9796f97c4de5b6fdc09f35ef19d6b83a7e6df6dfcb5cf091274606b4703'){throw '[mir4-t10-historical-4.0-digest]'}
Test-MIR4EnvironmentLockV1 $lockA|Out-Null
if(-not(($lockA|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/preview/mir4-environment-lock-v1.schema.json'))){throw '[mir4-t10-lock-schema]'}
$current=$a|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
foreach($version in @('4.2.21000','4.10.21000')){
  $current.mir.version=$version
  $currentLock=New-MIR4EnvironmentLockV1 $current -Capture 'observed'
  Test-MIR4EnvironmentLockV1 $currentLock|Out-Null
  if(-not(($currentLock|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/preview/mir4-environment-lock-v1.schema.json'))){throw "[mir4-t10-current-lock-schema] $version"}
}
foreach($version in @('3.2.21000','5.0.21000','4.02.21000','4.2.2100','4.2.210000','4.2.21000-dev')){
  $invalid=$a|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $invalid.mir.version=$version
  try{New-MIR4EnvironmentLockV1 $invalid -Capture 'observed'|Out-Null;throw "[mir4-t10-invalid-version-accepted] $version"}catch{if($_.Exception.Message-notmatch'^\[mir4-environment-lock-identity\]'){throw}}
}
$exactCapture=New-MIR4EnvironmentLockV1 $a -Capture 'engine-post-finalizer-exact'
if([string]$exactCapture.capture-cne'engine-post-finalizer-exact'){throw '[mir4-t10-exact-capture]'}
$nonString=$a|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
$nonString.mir.version=4021000
try{New-MIR4EnvironmentLockV1 $nonString -Capture 'observed'|Out-Null;throw '[mir4-t10-non-string-version-accepted]'}catch{if($_.Exception.Message-notmatch'^\[mir4-environment-lock-identity\]'){throw}}
$invalidLock=$lockA|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
$invalidLock.mir.version='5.0.21000'
Add-MIR4EnvironmentDigest $invalidLock|Out-Null
try{Test-MIR4EnvironmentLockV1 $invalidLock|Out-Null;throw '[mir4-t10-invalid-version-direct-validator-accepted]'}catch{if($_.Exception.Message-notmatch'^\[mir4-environment-lock-boundary\]'){throw}}

$lockSchema = Join-Path $RepoRoot 'spec/schemas/preview/mir4-environment-lock-v1.schema.json'
function Assert-T10EnvironmentLockParityReject {
  param([string]$Id,[scriptblock]$Mutate)
  $manifest = $a | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
  & $Mutate $manifest
  $constructorRejected = $false
  try { New-MIR4EnvironmentLockV1 $manifest | Out-Null } catch { $constructorRejected = $true }
  if (-not $constructorRejected) { throw "[mir4-t10-parity-constructor] $Id" }

  $candidate = $lockA | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
  & $Mutate $candidate
  Add-MIR4EnvironmentDigest $candidate | Out-Null
  $schemaRejected = $false
  try { $schemaRejected = -not (($candidate | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $lockSchema -ErrorAction Stop) } catch { $schemaRejected = $true }
  if (-not $schemaRejected) { throw "[mir4-t10-parity-schema] $Id" }
  $directRejected = $false
  try { Test-MIR4EnvironmentLockV1 $candidate | Out-Null } catch { $directRejected = $true }
  if (-not $directRejected) { throw "[mir4-t10-parity-direct] $Id" }
}

$parityCases = @(
  [pscustomobject]@{id='numeric-target';mutate={param($v)$v.target=210}},
  [pscustomobject]@{id='bad-engine-version';mutate={param($v)$v.engine.version='xxx'}},
  [pscustomobject]@{id='bad-mod-version';mutate={param($v)$v.mods[0].version='xxx'}},
  [pscustomobject]@{id='numeric-setting-name';mutate={param($v)$v.startup_settings[0].name=123}},
  [pscustomobject]@{id='blank-setting-name';mutate={param($v)$v.startup_settings[0].name='   '}},
  [pscustomobject]@{id='numeric-contract';mutate={param($v)$v.contracts[0]=123}},
  [pscustomobject]@{id='blank-contract';mutate={param($v)$v.contracts[0]='   '}},
  [pscustomobject]@{id='blank-extension-id';mutate={param($v)$v.extensions=@([pscustomobject]@{extension_id=' ';version='1.0.0';digest=('sha256:' + ('c'*64))})}},
  [pscustomobject]@{id='too-many-mods';mutate={param($v)$v.mods=@(0..512|ForEach-Object{[pscustomobject]@{name=('m{0:D3}'-f$_);version='1.0.0';sha256=('sha256:' + ('a'*64))}})}},
  [pscustomobject]@{id='too-many-settings';mutate={param($v)$v.startup_settings=@(0..2048|ForEach-Object{[pscustomobject]@{name=('s{0:D4}'-f$_);value=$true}})}},
  [pscustomobject]@{id='too-many-extensions';mutate={param($v)$v.extensions=@(0..256|ForEach-Object{[pscustomobject]@{extension_id=('org.example.e{0:D3}'-f$_);version='1.0.0';digest=('sha256:' + ('c'*64))}})}},
  [pscustomobject]@{id='too-many-contracts';mutate={param($v)$v.contracts=@(0..128|ForEach-Object{'contract/{0:D3}'-f$_})}}
)
foreach ($case in $parityCases) { Assert-T10EnvironmentLockParityReject -Id $case.id -Mutate $case.mutate }

$booleanSchema = $lockA | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
$booleanSchema.schema = $true
Add-MIR4EnvironmentDigest $booleanSchema | Out-Null
$booleanSchemaRejected = $false
try { $booleanSchemaRejected = -not (($booleanSchema | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $lockSchema -ErrorAction Stop) } catch { $booleanSchemaRejected = $true }
if (-not $booleanSchemaRejected) { throw '[mir4-t10-parity-schema] boolean-schema' }
try { Test-MIR4EnvironmentLockV1 $booleanSchema | Out-Null; throw '[mir4-t10-parity-direct] boolean-schema' } catch { if ($_.Exception.Message -cmatch '^\[mir4-t10-parity-direct\]') { throw } }

foreach($case in @(
  [pscustomobject]@{id='extra-setting';mutate={param($value)$value.startup_settings[0]|Add-Member -NotePropertyName extra -NotePropertyValue 'no'}},
  [pscustomobject]@{id='null-setting';mutate={param($value)$value.startup_settings[0].value=$null}},
  [pscustomobject]@{id='object-setting';mutate={param($value)$value.startup_settings[0].value=[pscustomobject]@{no='yes'}}},
  [pscustomobject]@{id='duplicate-setting';mutate={param($value)$value.startup_settings+=($value.startup_settings[0]|ConvertTo-Json -Depth 100|ConvertFrom-Json)}},
  [pscustomobject]@{id='bad-mod-name';mutate={param($value)$value.mods[0].name='bad mod'}},
  [pscustomobject]@{id='bad-extension-digest';mutate={param($value)$value.extensions=@([pscustomobject]@{extension_id='org.example.reference';version='1';digest='sha256:not-a-digest'})}}
)){
  $manifest=$a|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  & $case.mutate $manifest
  try{New-MIR4EnvironmentLockV1 $manifest|Out-Null;throw "[mir4-t10-constructor-accepted] $($case.id)"}catch{if($_.Exception.Message-match"^\[mir4-t10-constructor-accepted\]"){throw}}
}
$unsorted=$lockA|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
$unsorted.startup_settings=@($unsorted.startup_settings[1],$unsorted.startup_settings[0]);Add-MIR4EnvironmentDigest $unsorted|Out-Null
try{Test-MIR4EnvironmentLockV1 $unsorted|Out-Null;throw '[mir4-t10-unsorted-settings-direct-validator-accepted]'}catch{if($_.Exception.Message-notmatch'^\[mir4-environment-row-order\]'){throw}}
$extraLock=$lockA|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
$extraLock|Add-Member -NotePropertyName extra -NotePropertyValue $true;Add-MIR4EnvironmentDigest $extraLock|Out-Null
try{($extraLock|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/preview/mir4-environment-lock-v1.schema.json')|Out-Null;throw '[mir4-t10-extra-lock-schema-accepted]'}catch{if($_.Exception.Message-match'^\[mir4-t10-extra-lock-schema-accepted\]'){throw}}
try{Test-MIR4EnvironmentLockV1 $extraLock|Out-Null;throw '[mir4-t10-extra-lock-direct-validator-accepted]'}catch{if($_.Exception.Message-notmatch'^\[mir4-environment-lock-boundary\]'){throw}}

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
