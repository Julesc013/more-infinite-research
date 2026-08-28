param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/domain/canonicalization/CanonicalJsonV1.ps1')
. (Join-Path $repo 'tools/mir/application/release/ReleaseDag.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

function Assert-MIR4ReleaseToolingV1([bool]$Condition,[string]$Code,[string]$Detail=''){if(-not$Condition){throw "[$Code] $Detail"}}
function Invoke-MIR4ReleaseDagProbeV1($Value){try{$result=Test-MIR4ReleaseDag -Dag $Value;return [ordered]@{accepted=$true;result=[bool]$result;error=''}}catch{return [ordered]@{accepted=$false;result=$false;error=[string]$_.Exception.Message}}}
function Copy-MIR4ReleaseDagProbeV1($Value){return $Value|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$dag=Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/platform/mir4-preview-v0/release-dag.json')|ConvertFrom-Json -Depth 100
$identity=Copy-MIR4ReleaseDagProbeV1 $dag;$identity.kind='wrong'
$duplicate=Copy-MIR4ReleaseDagProbeV1 $dag;$duplicate.nodes+=Copy-MIR4ReleaseDagProbeV1 $duplicate.nodes[0]
$missing=Copy-MIR4ReleaseDagProbeV1 $dag;$missing.nodes[0].depends_on=@('absent')
$boundary=Copy-MIR4ReleaseDagProbeV1 $dag;$boundary.nodes[10].authorization='candidate-programme'
$cycle=Copy-MIR4ReleaseDagProbeV1 $dag;$cycle.nodes[0].depends_on=@('public-readback')
$record=[ordered]@{
  kind='MIR4ReleaseDagFunctionalProbeV1';schema=1;source_kind=[string]$dag.kind;source_schema=[int]$dag.schema;source_status=[string]$dag.status
  node_count=@($dag.nodes).Count;protected_mutation_count=@($dag.nodes|Where-Object{$_.mutation-in@('sign','seal','promote','tag','publish','delete')}).Count
  valid=Invoke-MIR4ReleaseDagProbeV1 $dag;identity=Invoke-MIR4ReleaseDagProbeV1 $identity;duplicate=Invoke-MIR4ReleaseDagProbeV1 $duplicate
  missing=Invoke-MIR4ReleaseDagProbeV1 $missing;boundary=Invoke-MIR4ReleaseDagProbeV1 $boundary;cycle=Invoke-MIR4ReleaseDagProbeV1 $cycle
}
$digest=Get-MIR4CanonicalDigestV1 -Value $record -Domain 'mir4:release-dag-functional-probe:1'
Assert-MIR4ReleaseToolingV1 ($digest-ceq'sha256:59043062e11420aee5daaeee51f8735f538b3091b0a87b43ec9c22e10743f99d') 'mir4-release-tooling-functional-parity' $digest
Assert-MIR4ReleaseToolingV1 ([bool]$record.valid.accepted-and[bool]$record.valid.result-and-not[bool]$record.boundary.accepted-and-not[bool]$record.cycle.accepted) 'mir4-release-tooling-result-abi'
Assert-MIR4ReleaseToolingV1 ([int]$record.node_count-eq20-and[int]$record.protected_mutation_count-eq6) 'mir4-release-tooling-authority-shape'
Assert-MIR4ReleaseToolingV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-release-tooling-package-mutation'
[pscustomobject][ordered]@{status='accepted';functional_parity_digest=$digest;node_count=20;protected_mutation_count=6;compatibility_entrypoint_count=1;package_source_sha256=$packageBefore;package_visible=$false;release_transition_authority=$false}
