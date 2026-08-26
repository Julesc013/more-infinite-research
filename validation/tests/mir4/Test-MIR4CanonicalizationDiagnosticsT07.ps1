param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/CanonicalJsonV1.ps1')
. (Join-Path $repo 'tools/lib/mir4/DiagnosticsV1.ps1')
. (Join-Path $repo 'tools/lib/mir4/ModuleEcosystem.ps1')
. (Join-Path $repo 'tools/lib/mir4/ExperimentalApiSdk.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
Assert-MIR4PackagePresentationV1 -RepoRoot $repo -PackageSourceSha256 $packageBefore|Out-Null
$schemaPairs=[ordered]@{
  'spec/canonicalization/mir-canonical-json-v1.json'='spec/schemas/preview/mir4-canonical-json-v1.schema.json'
  'spec/api/mir4-v1/schema-namespace.json'='spec/schemas/preview/mir4-schema-namespace-v1.schema.json'
  'spec/api/mir4-v1/diagnostics.json'='spec/schemas/preview/mir4-diagnostic-registry-v1.schema.json'
  'spec/api/mir4-v1/compatibility.json'='spec/schemas/preview/mir4-preview-compatibility-policy-v1.schema.json'
  'fixtures/mir4-canonical-json-v1/vectors.json'='spec/schemas/preview/mir4-canonical-json-vectors-v1.schema.json'
}
foreach($entry in $schemaPairs.GetEnumerator()){
  if(-not((Get-Content -Raw -LiteralPath (Join-Path $repo $entry.Key))|Test-Json -SchemaFile (Join-Path $repo $entry.Value))){
    throw "[mir4-t07-schema] $($entry.Key)"
  }
}

$contract=Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/canonicalization/mir-canonical-json-v1.json')|ConvertFrom-Json -Depth 100
if($contract.identifier-cne'mir-canonical-json/1'-or$contract.encoding.bom_allowed-or
   $contract.unicode.normalization-cne'NFC'-or$contract.objects.property_order-cne'ascending-UTF-16-code-unit-order'-or
   $contract.arrays.generic_order-cne'preserve'-or$contract.numbers.minimum-ne-9007199254740991-or
   $contract.numbers.maximum-ne9007199254740991-or$contract.limits.maximum_depth-ne64-or
   $contract.timestamps.grammar-cne'yyyy-MM-ddTHH:mm:ssZ'-or$contract.target_ids.grammar-cne'^f[0-9]{3}$'){
  throw '[mir4-t07-canonical-contract]'
}

$namespace=Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/api/mir4-v1/schema-namespace.json')|ConvertFrom-Json -Depth 100
if($namespace.namespace-cne'https://julesc013.github.io/more-infinite-research/schemas/mir4/v1/'-or@($namespace.schemas).Count-lt7-or
   @($namespace.schemas.id|Sort-Object -Unique).Count-ne@($namespace.schemas).Count-or
   @($namespace.schemas.path|Sort-Object -Unique).Count-ne@($namespace.schemas).Count){
  throw '[mir4-t07-schema-namespace]'
}
foreach($row in $namespace.schemas){
  $schema=Get-Content -Raw -LiteralPath (Join-Path $repo ([string]$row.path))|ConvertFrom-Json -Depth 100
  if([string]$schema.'$id'-cne[string]$row.id-or[string]$row.id-match'\.invalid/'){throw "[mir4-t07-schema-id] $($row.path)"}
}

$corpus=Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/mir4-canonical-json-v1/vectors.json')|ConvertFrom-Json -Depth 100
if(@($corpus.positive).Count-lt12-or@($corpus.negative).Count-lt16){throw '[mir4-t07-vector-count]'}
foreach($vector in $corpus.positive){
  $actual=ConvertFrom-MIR4CanonicalJsonTextV1 -Json ([string]$vector.input_json)
  if($actual-cne[string]$vector.canonical_json){throw "[mir4-t07-positive-vector] $($vector.id)"}
}
foreach($vector in $corpus.negative){
  try{ConvertFrom-MIR4CanonicalJsonTextV1 -Json ([string]$vector.input_json)|Out-Null;throw "[mir4-t07-negative-accepted] $($vector.id)"}
  catch{if(-not$_.Exception.Message.StartsWith("[$([string]$vector.diagnostic)]")){throw}}
}

$python=(Get-Command python -ErrorAction Stop).Source
$pythonResult=& $python (Join-Path $repo 'spec/canonicalization/reference/mir4_canonical_json_v1.py') --vectors (Join-Path $repo 'fixtures/mir4-canonical-json-v1/vectors.json')
if($LASTEXITCODE-ne0){throw '[mir4-t07-python-reference-exit]'}
$pythonRecord=$pythonResult|ConvertFrom-Json
if(-not$pythonRecord.passed-or@($pythonRecord.failures).Count-ne0-or$pythonRecord.positive-ne@($corpus.positive).Count-or$pythonRecord.negative-ne@($corpus.negative).Count){
  throw '[mir4-t07-cross-runtime-parity]'
}

$digestValue=[pscustomobject][ordered]@{kind='MIR4ApiResponseV1';schema=1;value='same';digest=''}
$apiDigest=Get-MIR4CanonicalDigestV1 -Value $digestValue -Domain 'mir4:api-response-v1' -OmitTopLevelDigest
$mepDigest=Get-MIR4CanonicalDigestV1 -Value $digestValue -Domain 'mir4:extension-envelope-v1' -OmitTopLevelDigest
if($apiDigest-ceq$mepDigest-or$apiDigest-notmatch'^sha256:[0-9a-f]{64}$'){throw '[mir4-t07-domain-separation]'}
$untypedDomain=& { Set-StrictMode -Version Latest; Get-MIR4RecordDigestDomainV1 -Value ([pscustomobject][ordered]@{schema=1;value='untyped'}) }
if($untypedDomain-cne'mir4:module-value-v1'){throw '[mir4-t07-untyped-record-domain]'}
Test-MIR4CanonicalTimestampV1 '2026-08-26T00:00:00Z'|Out-Null
Test-MIR4CanonicalTargetIdV1 'f210'|Out-Null
foreach($bad in @('2026-08-26T00:00:00+10:00','2026-08-26T00:00:00.000Z')){
  try{Test-MIR4CanonicalTimestampV1 $bad|Out-Null;throw '[mir4-t07-timestamp-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-canon-timestamp]')){throw}}
}
try{Test-MIR4CanonicalTargetIdV1 'F210'|Out-Null;throw '[mir4-t07-target-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-canon-target-id]')){throw}}

$registry=Get-MIR4DiagnosticRegistryV1 -RepoRoot $repo
if(@($registry.diagnostics).Count-lt39-or@($registry.diagnostics.legacy_id|Sort-Object -Unique).Count-ne@($registry.diagnostics).Count){
  throw '[mir4-t07-diagnostic-registry]'
}
$diagnostics=@(
  New-MIR4DiagnosticV1 -RepoRoot $repo -Code 'MIR4-CANON-002' -Path '$.number'
  New-MIR4DiagnosticV1 -RepoRoot $repo -Code 'MIR4-API-001' -Path '$.availability'
)
$sorted=@(Sort-MIR4DiagnosticsV1 -Diagnostics $diagnostics)
if($sorted[0].code-cne'MIR4-API-001'-or(Format-MIR4DiagnosticV1 $sorted[0])-notmatch'^\[MIR4-API-001\] error'){throw '[mir4-t07-diagnostic-order-render]'}

$compatibility=Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/api/mir4-v1/compatibility.json')|ConvertFrom-Json -Depth 100
if($compatibility.current_canonicalization-cne'mir-canonical-json/1'-or$compatibility.v0.status-cne'deprecated-migration-input-only'-or
   $compatibility.v0.write-cne'forbidden'-or$compatibility.v1.schema_ids-cne'permanent-and-never-reassigned'-or
   $compatibility.v1.mutation_authority-or$compatibility.v1.public_support_authority){
  throw '[mir4-t07-compatibility-policy]'
}

$reference=New-MIR4ReferenceExtensionV1 -RepoRoot $repo
Test-MIR4MepV1Envelope -Envelope $reference -RepoRoot $repo|Out-Null
$response=New-MIR4ApiV1Response -RepoRoot $repo -Surface query -Target f210 -Items @([ordered]@{id='canonical'})
if($reference.canonicalization-cne'mir-canonical-json/1'-or$response.canonicalization-cne'mir-canonical-json/1'-or
   $reference.digest-cne(Get-MIR4ModuleDigest $reference)-or$response.digest-cne(Get-MIR4ModuleDigest $response)){
  throw '[mir4-t07-v1-record-digest]'
}
$legacy=$reference|ConvertTo-Json -Depth 100|ConvertFrom-Json
$legacy.canonicalization='mir-canonical-json-v0'
try{Test-MIR4MepV1Envelope -Envelope $legacy -RepoRoot $repo|Out-Null;throw '[mir4-t07-v0-canonicalization-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-mep-v1-schema]')){throw}}

Invoke-MIR4SdkGenerate -RepoRoot $repo -Check
foreach($path in @(
  'sdk/preview/mir4/canonical-json-v1/powershell/MIR4.CanonicalJson.V1.psm1',
  'sdk/preview/mir4/canonical-json-v1/python/mir4_canonical_json_v1.py',
  'sdk/preview/mir4/api-v1/diagnostics.json',
  'sdk/preview/mir4/api-v1/compatibility.json',
  'docs/reference/mir4-canonical-json-v1.md'
)){if(-not(Test-Path -LiteralPath (Join-Path $repo $path) -PathType Leaf)){throw "[mir4-t07-projection] $path"}}

if((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-cne$packageBefore){
  throw '[mir4-t07-package-source-mutation]'
}
Write-Host '[ok] MIR 4 T07 permanent schema namespace, canonical JSON V1, stable diagnostics, compatibility policy, and cross-runtime vectors passed.'
