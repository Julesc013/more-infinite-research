param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'

. (Join-Path $RepoRoot 'tools/lib/mir4/MepDiscovery.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PackagePresentation.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')

$before=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
Assert-MIR4PackagePresentationV1 -RepoRoot $RepoRoot -PackageSourceSha256 $before|Out-Null
$emitterPath=Join-Path $RepoRoot 'prototypes/mir/emit/mod_data.lua'
$emitterBefore=(Get-FileHash -LiteralPath $emitterPath -Algorithm SHA256).Hash

$contract=Get-MIR4F210MepDiscoveryContractV1 -RepoRoot $RepoRoot
if([string]$contract.admission-cne'blocked-by-terminal-emitter'-or[string]$contract.host_absence-cne'inert'-or
   [int]$contract.maximum_extension_records-ne32-or[bool]$contract.package_visible-or[bool]$contract.player_mutation_authorized-or
   [bool]$contract.prototype_write_authorized-or[bool]$contract.public_support_authorized-or[bool]$contract.release_authority){throw '[mir4-t11-contract]'}

function Read-T11Snapshot([string]$RelativePath){
  return Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $RelativePath)|ConvertFrom-Json -Depth 100
}
$inputA=Read-T11Snapshot 'fixtures/mir4-mep-discovery-v1/positive/order-a.json'
$inputB=Read-T11Snapshot 'fixtures/mir4-mep-discovery-v1/positive/order-b.json'
$inputDigest=[string]$inputA.records[0].data.digest
$a=New-MIR4F210MepDiscoveryV1 -RepoRoot $RepoRoot -Snapshot $inputA
$b=New-MIR4F210MepDiscoveryV1 -RepoRoot $RepoRoot -Snapshot $inputB
foreach($result in @($a,$b)){
  Test-MIR4F210MepDiscoveryResultV1 -RepoRoot $RepoRoot -Result $result|Out-Null
  if([string]$result.result-cne'shadow-complete'-or[int]$result.counts.snapshot_records-ne3-or
     [int]$result.counts.matching_records-ne2-or[int]$result.counts.ignored_records-ne1-or
     [int]$result.counts.accepted_records-ne2-or[int]$result.counts.quarantined_records-ne0-or
     @($result.shadow_plans).Count-ne2-or@($result.diagnostics).Count-ne0){throw '[mir4-t11-positive-result]'}
  if(($result.closure.order-join'|')-cne'org.more-infinite-research.platform|org.more-infinite-research.reference|org.example.discovery-addon'){throw '[mir4-t11-closure-order]'}
  foreach($flag in @('package_visible','player_mutation_authorized','prototype_write_authorized','public_support_authorized','release_authority')){
    if([bool]$result.$flag){throw "[mir4-t11-authority] $flag"}
  }
  foreach($plan in @($result.shadow_plans)){
    if([bool]$plan.authoritative_output-or[bool]$plan.player_mutation_authorized-or[bool]$plan.prototype_write_authorized-or[bool]$plan.public_support_claim){throw '[mir4-t11-shadow-plan-authority]'}
  }
}
if([string]$a.digest-cne[string]$b.digest){throw '[mir4-t11-permutation-digest]'}
$a.records[0].extension_id='org.example.mutated-return'
if([string]$inputA.records[0].data.digest-cne$inputDigest){throw '[mir4-t11-input-mutated]'}

$hostAbsent=New-MIR4F210MepDiscoveryV1 -RepoRoot $RepoRoot -Snapshot (Read-T11Snapshot 'fixtures/mir4-mep-discovery-v1/positive/host-absent.json')
if([string]$hostAbsent.result-cne'host-absent-inert'-or@($hostAbsent.records).Count-ne0-or$null-ne$hostAbsent.closure-or
   @($hostAbsent.shadow_plans).Count-ne0-or(@($hostAbsent.diagnostics.code)-join'|')-cne'MIR4-MEP-016'){throw '[mir4-t11-host-absence]'}

$conflict=New-MIR4F210MepDiscoveryV1 -RepoRoot $RepoRoot -Snapshot (Read-T11Snapshot 'fixtures/mir4-mep-discovery-v1/negative/conflict.json')
if([string]$conflict.result-cne'quarantined'-or[int]$conflict.counts.accepted_records-ne0-or
   [int]$conflict.counts.quarantined_records-ne2-or(@($conflict.diagnostics.code)-join'|')-cne'MIR4-MEP-010'){throw '[mir4-t11-conflict]'}
$invalid=New-MIR4F210MepDiscoveryV1 -RepoRoot $RepoRoot -Snapshot (Read-T11Snapshot 'fixtures/mir4-mep-discovery-v1/negative/invalid-envelope.json')
if([string]$invalid.result-cne'quarantined'-or[int]$invalid.counts.accepted_records-ne0-or
   (@($invalid.diagnostics.code)-join'|')-cne'MIR4-MEP-002'){throw '[mir4-t11-invalid-envelope]'}

$duplicate=Read-T11Snapshot 'fixtures/mir4-mep-discovery-v1/positive/order-a.json'
$duplicate.records[1].name=$duplicate.records[0].name
try{Test-MIR4F210ModDataSnapshotV1 -RepoRoot $RepoRoot -Snapshot $duplicate|Out-Null;throw '[mir4-t11-duplicate-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-mep-discovery-duplicate-prototype]')){throw}}
$over=Read-T11Snapshot 'fixtures/mir4-mep-discovery-v1/positive/order-a.json'
$template=$over.records[0]
$over.records=@(0..32|ForEach-Object{[pscustomobject][ordered]@{name=('extension-{0:d2}'-f$_);data_type=[string]$template.data_type;data=$template.data}})
try{Test-MIR4F210ModDataSnapshotV1 -RepoRoot $RepoRoot -Snapshot $over|Out-Null;throw '[mir4-t11-cardinality-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-mep-discovery-cardinality]')){throw}}

$reference=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'sdk/preview/mir4/reference/f210-mep-discovery-v1.json')|ConvertFrom-Json -Depth 100
if([string]$reference.digest-cne[string]$b.digest){throw '[mir4-t11-reference-drift]'}
$resultSchema=Join-Path $RepoRoot 'spec/schemas/preview/mir4-f210-mep-discovery-result-v1.schema.json'
if(-not(($reference|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile $resultSchema)){throw '[mir4-t11-result-schema]'}

$cliRoot=Join-Path $RepoRoot 'build/results/mir4-t11-mep-discovery'
& (Join-Path $RepoRoot 'tools/commands/mir4/Invoke-MIR4Extension.ps1') -Command discover -RepoRoot $RepoRoot -DiscoveryPath 'fixtures/mir4-mep-discovery-v1/positive/order-b.json' -OutputRoot $cliRoot|Out-Null
$cli=Get-Content -Raw -LiteralPath (Join-Path $cliRoot 'f210-mep-discovery.json')|ConvertFrom-Json -Depth 100
if([string]$cli.digest-cne[string]$reference.digest){throw '[mir4-t11-cli]'}

Invoke-MIR4PlatformGenerate -RepoRoot $RepoRoot -Check|Out-Null
$platform=Test-MIR4PlatformConformance -RepoRoot $RepoRoot
if(-not[bool]$platform){throw '[mir4-t11-platform-conformance]'}
$lua=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'sdk/preview/mir4/mep-v1/lua/mir4_mep_v1.lua')
foreach($needle in @('function M.discover_mod_data','more-infinite-research.extension.v1','host-absent-inert','dependency-cycle',"status='validated'")){
  if(-not$lua.Contains($needle)){throw "[mir4-t11-lua-collector] $needle"}
}
if($lua-match'data\s*:\s*extend|data\.raw\s*\[[^\]]+\]\s*='){throw '[mir4-t11-lua-prototype-write]'}

$shipped=@(Get-MIRPackageSourceFiles -RepoRoot $RepoRoot)
foreach($path in @('tools/lib/mir4/MepDiscovery.ps1','docs/reference/mir4-f210-mep-discovery.md','fixtures/mir4-mep-discovery-v1','sdk/preview/mir4/reference/f210-mep-discovery-v1.json','spec/schemas/preview/mir4-f210-mod-data-snapshot-v1.schema.json','spec/schemas/preview/mir4-f210-mep-discovery-result-v1.schema.json')){
  if(@($shipped|Where-Object{$_-eq$path-or$_.StartsWith($path+'/')}).Count){throw "[mir4-t11-package-visible] $path"}
}
if((Get-FileHash -LiteralPath $emitterPath -Algorithm SHA256).Hash-cne$emitterBefore){throw '[mir4-t11-emitter-mutation]'}
$after=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
if($after-cne$before){throw '[mir4-t11-package-mutation]'}
Write-Host '[ok] MIR 4 T11 read-only F210 MEP discovery passed: deterministic selection, validation, closure, conflict quarantine, inert host absence, shadow explanation, and unchanged player emitter.'
