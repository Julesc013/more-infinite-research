$script:MIR4PlatformInputPaths = @(
  'mir.toml',
  'spec/platform/mir4-preview-v0/platform.json',
  'spec/platform/mir4-preview-v0/release-dag.json',
  'spec/api/mir4-v0/contracts.json',
  '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV5.json',
  '.mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV3.json',
  '.mir/releases/waves/mir4-r0/MIR4-Historical-Private-Candidate-AuthorizationV1.json',
  '.mir/compatibility.yml',
  '.mir/streams.yml',
  '.mir/fixtures.yml',
  '.mir/modules.yml',
  '.mir/control/repository-fixed-point.json',
  'tools/lib/mir4/ExperimentalApiSdk.ps1',
  'tools/lib/mir4/SafetyKernel.ps1',
  'tools/lib/mir4/PolicyEngine.ps1',
  'tools/lib/mir4/NormalizedCompiler.ps1',
  'tools/lib/mir4/RuntimeStateModel.ps1',
  'tools/lib/mir4/ProcessIR.ps1',
  'tools/lib/mir4/ReleaseDag.ps1',
  'tools/lib/mir4/RepositoryFixedPoint.ps1'
)

function Get-MIR4PlatformRepoRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Get-MIR4PlatformFileSha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function ConvertTo-MIR4PlatformCanonicalValue {
  param($Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [string] -or $Value -is [bool] -or $Value -is [ValueType]) { return $Value }
  if ($Value -is [Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)) {
      $result[$key] = ConvertTo-MIR4PlatformCanonicalValue $Value[$key]
    }
    return $result
  }
  if ($Value -is [pscustomobject]) {
    $result = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Sort-Object Name -CaseSensitive)) {
      $result[$property.Name] = ConvertTo-MIR4PlatformCanonicalValue $property.Value
    }
    return $result
  }
  if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    Write-Output -NoEnumerate @($Value | ForEach-Object { ConvertTo-MIR4PlatformCanonicalValue $_ })
    return
  }
  return $Value
}

function ConvertTo-MIR4PlatformCanonicalJson {
  param([Parameter(Mandatory)]$Value)
  return ((ConvertTo-MIR4PlatformCanonicalValue $Value) | ConvertTo-Json -Depth 100 -Compress)
}

function Get-MIR4PlatformDigest {
  param([Parameter(Mandatory)]$Value)
  $material = [ordered]@{}
  foreach ($property in $Value.PSObject.Properties) {
    if ($property.Name -ne 'digest') { $material[$property.Name] = $property.Value }
  }
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4PlatformCanonicalJson $material))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return 'sha256:' + ([BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()) }
  finally { $sha.Dispose() }
}

function Add-MIR4PlatformDigest {
  param([Parameter(Mandatory)]$Value)
  $Value.digest = Get-MIR4PlatformDigest $Value
  return $Value
}

function Get-MIR4PlatformInputs {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  return @(
    foreach ($relative in $script:MIR4PlatformInputPaths) {
      $path = Join-Path $repo $relative
      if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-platform-input-missing] $relative" }
      [ordered]@{ path=$relative; sha256=(Get-MIR4PlatformFileSha256 $path) }
    }
  )
}

function Get-MIR4PlatformTargetKey {
  param([Parameter(Mandatory)][string]$Code)
  return 'f' + $Code
}

function Get-MIR4PlatformDistributionVersion {
  param([Parameter(Mandatory)][string]$Code)
  return '4.0.' + $Code + '00'
}

function Get-MIR4PlatformPredecessorPath {
  param([AllowNull()][string]$Release)
  if ([string]::IsNullOrWhiteSpace($Release)) { return $null }
  return ".mir/releases/terminal/baselines/$Release/normalized-snapshot.json"
}

. (Join-Path $PSScriptRoot 'SafetyKernel.ps1')
. (Join-Path $PSScriptRoot 'PolicyEngine.ps1')
. (Join-Path $PSScriptRoot 'NormalizedCompiler.ps1')
. (Join-Path $PSScriptRoot 'RuntimeStateModel.ps1')
. (Join-Path $PSScriptRoot 'ProcessIR.ps1')
. (Join-Path $PSScriptRoot 'ReleaseDag.ps1')

function Get-MIR4TargetProviderRecords {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return @(New-MIR4NormalizedTargetProviders -RepoRoot $RepoRoot)
}

function Get-MIR4CompilationRunRecords {
  param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)]$Providers)
  return @(New-MIR4NormalizedCompilationRuns -RepoRoot $RepoRoot -Providers $Providers)
}

function Get-MIR4RuntimeStateInventory {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return New-MIR4RuntimeStateInventory -RepoRoot $RepoRoot
}

function Get-MIR4ProcessIRInventory {
  param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)]$PlatformSpec)
  return New-MIR4ProcessIRInventory -RepoRoot $RepoRoot -PlatformSpec $PlatformSpec
}

function Get-MIR4OpportunityCatalogue {
  param([Parameter(Mandatory)]$PlatformSpec,[Parameter(Mandatory)]$ProcessIR)
  return New-MIR4OpportunityCatalogue -PlatformSpec $PlatformSpec -ProcessIR $ProcessIR
}

function Get-MIR4MepSchema {
  param([Parameter(Mandatory)]$PlatformSpec)
  return [ordered]@{
    '$schema'='https://json-schema.org/draft/2020-12/schema'
    '$id'='https://mir.invalid/preview/mir4-mep-v0.schema.json'
    title='MIR Extension Protocol V0 Preview'
    type='object'; additionalProperties=$false
    required=@('kind','schema','extension_id','targets','fragments','canonicalization','digest')
    properties=[ordered]@{
      kind=@{ const='MIR4ExtensionEnvelopeV0' }
      schema=@{ const=0 }
      extension_id=@{ type='string'; pattern='^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$' }
      targets=@{ type='array'; minItems=1; maxItems=17; uniqueItems=$true; items=@{ type='string'; pattern='^f[0-9]{3}$' } }
      fragments=@{ type='array'; minItems=1; maxItems=64; items=@{ type='object'; additionalProperties=$false; required=@('id','kind','data'); properties=@{ id=@{type='string';pattern='^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$'}; kind=@{enum=@($PlatformSpec.mep_fragments)}; data=@{type='object';maxProperties=64;additionalProperties=$true} } } }
      canonicalization=@{ const='mir-canonical-json-v0' }
      digest=@{ type='string'; pattern='^sha256:[0-9a-f]{64}$' }
    }
  }
}

function Test-MIR4MepForbiddenValue {
  param([Parameter(Mandatory)][AllowNull()]$Value, [Parameter(Mandatory)][string[]]$Forbidden, [string]$Path='$')
  if ($null -eq $Value) { return }
  if ($Value -is [pscustomobject]) {
    foreach ($property in $Value.PSObject.Properties) {
      if ([string]$property.Name -in $Forbidden) { throw "[mir4-mep-forbidden-field] $Path.$($property.Name)" }
      Test-MIR4MepForbiddenValue -Value $property.Value -Forbidden $Forbidden -Path "$Path.$($property.Name)"
    }
  } elseif ($Value -is [Collections.IDictionary]) {
    foreach ($key in $Value.Keys) {
      if ([string]$key -in $Forbidden) { throw "[mir4-mep-forbidden-field] $Path.$key" }
      Test-MIR4MepForbiddenValue -Value $Value[$key] -Forbidden $Forbidden -Path "$Path.$key"
    }
  } elseif ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    $index = 0
    foreach ($item in $Value) { Test-MIR4MepForbiddenValue -Value $item -Forbidden $Forbidden -Path "$Path[$index]"; $index++ }
  }
}

function Test-MIR4MepEnvelope {
  param([Parameter(Mandatory)]$Envelope, [Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $spec = Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/platform/mir4-preview-v0/platform.json') | ConvertFrom-Json
  $schema = Join-Path $repo 'spec/schemas/preview/mir4-mep-v0.schema.json'
  try { $valid = (($Envelope | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schema -ErrorAction Stop) }
  catch { throw '[mir4-mep-schema] Envelope schema validation failed.' }
  if (-not $valid) { throw '[mir4-mep-schema] Envelope schema validation failed.' }
  Test-MIR4MepForbiddenValue -Value $Envelope -Forbidden @($spec.mep_forbidden_fields)
  $ids = @($Envelope.fragments | ForEach-Object { [string]$_.id })
  if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw '[mir4-mep-duplicate-fragment] Fragment IDs must be unique.' }
  if ([string]$Envelope.digest -cne (Get-MIR4PlatformDigest $Envelope)) { throw '[mir4-mep-digest] Envelope digest mismatch.' }
  return $true
}

function New-MIR4ReferenceExtension {
  $record = [pscustomobject][ordered]@{
    kind='MIR4ExtensionEnvelopeV0'; schema=0; extension_id='org.more-infinite-research.reference'; targets=@('f210','f200','f110','f100')
    fragments=@(
      [ordered]@{id='org.more-infinite-research.compatibility';kind='CompatibilityFragment';data=[ordered]@{subjects=@('reference-intermediate');disposition='preserve-opaque'}},
      [ordered]@{id='org.more-infinite-research.profile';kind='ProfileFragment';data=[ordered]@{profile='reference-safe';settings=@{}}},
      [ordered]@{id='org.more-infinite-research.proof';kind='ProofFragment';data=[ordered]@{fixtures=@('reference-positive');claim_level='load-checked'}},
      [ordered]@{id='org.more-infinite-research.presentation';kind='PresentationFragment';data=[ordered]@{title='MIR 4 V0 reference extension';summary='Data-only conformance consumer.'}},
      [ordered]@{id='org.more-infinite-research.capability';kind='CapabilityRequirement';data=[ordered]@{all_of=@('query.read','support.snapshot')}},
      [ordered]@{id='org.more-infinite-research.dependency';kind='ExtensionDependency';data=[ordered]@{extension_id='org.more-infinite-research.platform';constraint='v0-preview'}},
      [ordered]@{id='org.more-infinite-research.conflict';kind='ExtensionConflict';data=[ordered]@{extension_ids=@()}},
      [ordered]@{id='org.more-infinite-research.finalization';kind='FinalizationRequirement';data=[ordered]@{phase='after-normalization';writes_allowed=$false}}
    )
    canonicalization='mir-canonical-json-v0'; digest=''
  }
  return Add-MIR4PlatformDigest $record
}

function Get-MIR4InspectorHtml {
  return @'
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>MIR 4 Inspector V0 Preview</title><style>body{font:15px system-ui;max-width:1100px;margin:2rem auto;padding:0 1rem;color:#20242a}header{display:flex;gap:1rem;align-items:center}section{border:1px solid #ccd3db;border-radius:8px;padding:1rem;margin:1rem 0}pre{white-space:pre-wrap;overflow:auto;background:#f5f7f9;padding:1rem}.badge{padding:.2rem .5rem;border-radius:1rem;background:#fff0bf}dt{font-weight:700}dd{margin:0 0 .5rem}</style></head><body><header><h1>MIR 4 Inspector</h1><span class="badge">V0 preview · read only</span></header><p>Select a generated Query API, support, compilation, runtime, or ProcessIR JSON record. Nothing is uploaded or mutated.</p><input id="file" type="file" accept="application/json"><section><h2>Overview</h2><dl id="overview"></dl></section><section><h2>Capabilities</h2><pre id="capabilities">No snapshot loaded.</pre></section><section><h2>Research streams</h2><pre id="streams">No snapshot loaded.</pre></section><section><h2>Diagnostics</h2><pre id="diagnostics">No snapshot loaded.</pre></section><section><h2>Settings / profile</h2><pre id="profile">No snapshot loaded.</pre></section><button id="export" disabled>Export support snapshot</button><script>let value=null;const show=(id,v)=>document.getElementById(id).textContent=JSON.stringify(v??[],null,2);const overview=v=>{const root=document.getElementById('overview');root.replaceChildren();for(const key of ['kind','schema','maturity','digest']){const dt=document.createElement('dt'),dd=document.createElement('dd');dt.textContent=key;dd.textContent=String(v[key]??'');root.append(dt,dd)}};document.getElementById('file').onchange=async e=>{try{value=JSON.parse(await e.target.files[0].text());overview(value);const p=value.payload||value;show('capabilities',value.capabilities||p.capabilities);show('streams',p.streams||p.channels);show('diagnostics',p.diagnostics||value.diagnostics);show('profile',p.profile||p.settings||p.state_specs);document.getElementById('export').disabled=false}catch(error){value=null;show('diagnostics',{code:'mir4-inspector-invalid-json',message:String(error)});document.getElementById('export').disabled=true}};document.getElementById('export').onclick=()=>{const blob=new Blob([JSON.stringify(value,null,2)+'\n'],{type:'application/json'}),a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='mir4-support-snapshot.json';a.click();URL.revokeObjectURL(a.href)};</script></body></html>
'@
}

function Get-MIR4PlatformGeneratedFiles {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  . (Join-Path $repo 'tools/lib/mir4/ExperimentalApiSdk.ps1')
  $platform = Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/platform/mir4-preview-v0/platform.json') | ConvertFrom-Json
  $releaseDag = Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/platform/mir4-preview-v0/release-dag.json') | ConvertFrom-Json
  Test-MIR4ReleaseDag -Dag $releaseDag | Out-Null
  $providers = @(Get-MIR4TargetProviderRecords $repo)
  $affectedTargets = New-MIR4AffectedTargetPlan -Providers $providers
  $runs = @(Get-MIR4CompilationRunRecords -RepoRoot $repo -Providers $providers)
  $runtime = Get-MIR4RuntimeStateInventory $repo
  $process = Get-MIR4ProcessIRInventory -RepoRoot $repo -PlatformSpec $platform
  $opportunities = Get-MIR4OpportunityCatalogue -PlatformSpec $platform -ProcessIR $process
  $mepSchema = Get-MIR4MepSchema $platform
  $extension = New-MIR4ReferenceExtension
  $shadowExtensionRun = New-MIR4ShadowExtensionCompilation -RepoRoot $repo -TargetId 'f210' -Envelope $extension
  $processSafeFixture = [ordered]@{schema=0;kind='MIR4ProcessIRSafetyFixtureV0';id='bounded-reference-loop';expected_status='accepted-for-policy-evaluation';contribution=[ordered]@{subject='process.reference.bounded';operations=@('data-only-fragment');evidence=@('fixture:bounded-reference-loop');positive_cycle=$true;proven_bounded=$true;owner_opaque=$false;owner_rewrite=$false;requested_disposition='preserve'}}
  $processUnsafeFixture = [ordered]@{schema=0;kind='MIR4ProcessIRSafetyFixtureV0';id='unbounded-reference-loop';expected_status='rejected';expected_violation='unbounded-positive-cycle';contribution=[ordered]@{subject='process.reference.unbounded';operations=@('data-only-fragment');evidence=@('fixture:unbounded-reference-loop');positive_cycle=$true;proven_bounded=$false;owner_opaque=$false;owner_rewrite=$false;requested_disposition='handle'}}
  $primary = $providers | Where-Object { $_.id -eq 'f210' }
  $primaryRun = $runs | Where-Object { $_.target.id -eq 'f210' }
  $query = New-MIR4ApiRecord -Kind MIR4QuerySnapshotV0 -TargetId f210 -FactorioLine '2.1' -SourceVersion '4.0.0' -DistributionVersion '4.0.21000' -Capabilities @('query.read','support.snapshot','streams.read','diagnostics.read','settings.read') -Payload ([ordered]@{ provider=$primary; compilation=$primaryRun; streams=[ordered]@{ authority='.mir/streams.yml'; mode='read-only' }; diagnostics=@(); profile=[ordered]@{ maturity='preview'; mutation_allowed=$false } })
  $support = New-MIR4ApiRecord -Kind MIR4SupportSnapshotV0 -TargetId f210 -FactorioLine '2.1' -SourceVersion '4.0.0' -DistributionVersion '4.0.21000' -Capabilities @('support.snapshot') -Payload ([ordered]@{ target=$primary; maturity='candidate-programme-only'; public_claim=$false; evidence=@('target-provider','compilation-run','runtime-state-inventory','process-ir-inventory') })
  $components = @($platform.components | ForEach-Object { "| ``$($_.id)`` | $($_.maturity) | $($_.mode) |" }) -join "`n"
  $generatedDoc = "---`ntitle: `"MIR 4 Platform Component Matrix`"`nstatus: current`napplies_to: `"4.0.0 M4C01`"`naudience: developer`ndoc_type: reference`nowner: mir-maintainers`nlast_reviewed: 2026-08-18`nsupersedes: []`nsuperseded_by: []`n---`n# MIR 4 Platform Component Matrix`n`nGenerated from ``spec/platform/mir4-preview-v0/platform.json``.`n`n| Component | Maturity | Mode |`n| --- | --- | --- |`n$components`n`nThe conformance gate enforces the eight non-interference rules and keeps every non-stable surface outside player packages.`n"
  $psBinding = @'
# Generated standalone MIR Extension Protocol V0 preview binding.
function ConvertTo-MIR4MepCanonicalValue($Value){
  if($null-eq$Value){return $null}
  if($Value-is[string]-or$Value-is[bool]-or$Value-is[ValueType]){return $Value}
  if($Value-is[Collections.IDictionary]){$result=[ordered]@{};foreach($key in @($Value.Keys|ForEach-Object{[string]$_}|Sort-Object -CaseSensitive)){$result[$key]=ConvertTo-MIR4MepCanonicalValue $Value[$key]};return $result}
  if($Value-is[pscustomobject]){$result=[ordered]@{};foreach($property in @($Value.PSObject.Properties|Sort-Object Name -CaseSensitive)){$result[$property.Name]=ConvertTo-MIR4MepCanonicalValue $property.Value};return $result}
  if($Value-is[Collections.IEnumerable]-and$Value-isnot[string]){Write-Output -NoEnumerate @($Value|ForEach-Object{ConvertTo-MIR4MepCanonicalValue $_});return}
  return $Value
}
function ConvertTo-MIR4MepCanonicalJson{param([Parameter(Mandatory)]$Value)(ConvertTo-MIR4MepCanonicalValue $Value)|ConvertTo-Json -Depth 100 -Compress}
function Get-MIR4MepDigest{param([Parameter(Mandatory)]$Value)$material=[ordered]@{};foreach($property in $Value.PSObject.Properties){if($property.Name-ne'digest'){$material[$property.Name]=$property.Value}};$bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4MepCanonicalJson $material));$sha=[Security.Cryptography.SHA256]::Create();try{'sha256:'+([BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant())}finally{$sha.Dispose()}}
function Test-MIR4MepForbiddenValue{param([Parameter(Mandatory)][AllowNull()]$Value,[string]$Path='$')$forbidden=@('callback','callbacks','compiler_context','data_raw','executor','prototype','prototype_write','safety_kernel');if($null-eq$Value){return};if($Value-is[pscustomobject]){foreach($property in $Value.PSObject.Properties){if([string]$property.Name-in$forbidden){throw "[mir4-mep-forbidden-field] $Path.$($property.Name)"};Test-MIR4MepForbiddenValue $property.Value "$Path.$($property.Name)"}}elseif($Value-is[Collections.IDictionary]){foreach($key in $Value.Keys){if([string]$key-in$forbidden){throw "[mir4-mep-forbidden-field] $Path.$key"};Test-MIR4MepForbiddenValue $Value[$key] "$Path.$key"}}elseif($Value-is[Collections.IEnumerable]-and$Value-isnot[string]){$index=0;foreach($item in $Value){Test-MIR4MepForbiddenValue $item "$Path[$index]";$index++}}}
function Test-MIR4MepEnvelope{
  param([Parameter(Mandatory)]$Envelope,[string]$RepoRoot='')
  $schemaPath=if($RepoRoot-and(Test-Path -LiteralPath (Join-Path $RepoRoot 'spec/schemas/preview/mir4-mep-v0.schema.json') -PathType Leaf)){Join-Path $RepoRoot 'spec/schemas/preview/mir4-mep-v0.schema.json'}else{Join-Path $PSScriptRoot '../schema/mir4-mep-v0.schema.json'}
  try{$valid=(($Envelope|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile $schemaPath -ErrorAction Stop)}catch{throw '[mir4-mep-schema] Envelope schema validation failed.'}
  if(-not$valid){throw '[mir4-mep-schema] Envelope schema validation failed.'}
  Test-MIR4MepForbiddenValue $Envelope
  $ids=@($Envelope.fragments|ForEach-Object{[string]$_.id});if(@($ids|Sort-Object -Unique).Count-ne$ids.Count){throw '[mir4-mep-duplicate-fragment] Fragment IDs must be unique.'}
  if([string]$Envelope.digest-cne(Get-MIR4MepDigest $Envelope)){throw '[mir4-mep-digest] Envelope digest mismatch.'}
  return $true
}
Export-ModuleMember -Function Test-MIR4MepEnvelope,ConvertTo-MIR4MepCanonicalJson,Get-MIR4MepDigest
'@
  $luaBinding = @'
-- Generated MIR Extension Protocol V0 preview structural validator.
local M = {}
local kinds = {CompatibilityFragment=true,ProfileFragment=true,ProofFragment=true,PresentationFragment=true,CapabilityRequirement=true,ExtensionDependency=true,ExtensionConflict=true,FinalizationRequirement=true}
local forbidden = {callback=true,callbacks=true,compiler_context=true,data_raw=true,executor=true,prototype=true,prototype_write=true,safety_kernel=true}
local function scan(v)
  if type(v) ~= 'table' then return true end
  for k,item in pairs(v) do if forbidden[k] then return nil,'mir4-mep-forbidden-field' end; local ok,err=scan(item); if not ok then return nil,err end end
  return true
end
function M.validate(v)
  if type(v)~='table' or v.kind~='MIR4ExtensionEnvelopeV0' or v.schema~=0 or type(v.fragments)~='table' or #v.fragments<1 then return nil,'mir4-mep-schema' end
  local seen={}; for _,f in ipairs(v.fragments) do if type(f)~='table' or not kinds[f.kind] or type(f.id)~='string' or seen[f.id] or type(f.data)~='table' then return nil,'mir4-mep-schema' end; seen[f.id]=true end
  return scan(v)
end
return M
'@
  $inspectorPs = @'
param([Parameter(Mandatory)][string]$InputPath,[string]$OutputPath='')
$record=Get-Content -Raw -LiteralPath $InputPath|ConvertFrom-Json
$view=[ordered]@{kind=$record.kind;schema=$record.schema;maturity=$record.maturity;target=$record.target;capabilities=$record.capabilities;payload=$record.payload;diagnostics=$record.diagnostics;digest=$record.digest}
$json=$view|ConvertTo-Json -Depth 100
if($OutputPath){[IO.File]::WriteAllText($OutputPath,$json+"`n",[Text.UTF8Encoding]::new($false))}else{$json}
'@
  $conformancePs = @'
param([string]$SdkRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $SdkRoot 'api-v0/powershell/MIR4.Api.V0.psm1') -Force
Import-Module (Join-Path $SdkRoot 'powershell/MIR4.MEP.V0.psm1') -Force
if((ConvertTo-MIR4ApiCanonicalJson ([ordered]@{empty=@()})) -cne '{"empty":[]}' -or (ConvertTo-MIR4MepCanonicalJson ([ordered]@{empty=@()})) -cne '{"empty":[]}'){throw '[mir4-sdk-canonical-empty-array]'}
$query=Get-Content -Raw -LiteralPath (Join-Path $SdkRoot 'reference/query-snapshot-f210.json')|ConvertFrom-Json
Test-MIR4ApiRecord $query|Out-Null
$badApi=$query|ConvertTo-Json -Depth 100|ConvertFrom-Json;$badApi.digest='sha256:'+('0'*64)
try{Test-MIR4ApiRecord $badApi|Out-Null;throw '[mir4-sdk-negative-api-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-api-digest]')){throw}}
$extension=Get-Content -Raw -LiteralPath (Join-Path $SdkRoot 'reference-extension/extension.json')|ConvertFrom-Json
Test-MIR4MepEnvelope $extension|Out-Null
$badMep=$extension|ConvertTo-Json -Depth 100|ConvertFrom-Json;$badMep.fragments[0].data|Add-Member -NotePropertyName callback -NotePropertyValue run
try{Test-MIR4MepEnvelope $badMep|Out-Null;throw '[mir4-sdk-negative-mep-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-mep-forbidden-field]')){throw}}
Write-Host '[ok] standalone MIR 4 SDK V0 conformance passed.'
'@
  $lock = [ordered]@{ schema=1; kind='MIR4PlatformLockV0'; source_version='4.0.0'; candidate_wave='M4C01'; canonicalization='mir-canonical-json-v0'; inputs=(Get-MIR4PlatformInputs $repo); generated_by='tools/lib/mir4/PlatformPreview.ps1'; digest='' }
  $lockObject = [pscustomobject]$lock
  Add-MIR4PlatformDigest $lockObject | Out-Null
  $files = [ordered]@{
    'mir.lock' = (ConvertTo-MIR4PlatformCanonicalJson $lockObject) + "`n"
    'spec/schemas/preview/mir4-mep-v0.schema.json' = (ConvertTo-MIR4PlatformCanonicalJson $mepSchema) + "`n"
    'sdk/preview/mir4/schema/mir4-mep-v0.schema.json' = (ConvertTo-MIR4PlatformCanonicalJson $mepSchema) + "`n"
    'sdk/preview/mir4/powershell/MIR4.MEP.V0.psm1' = $psBinding.Replace("`r`n","`n")
    'sdk/preview/mir4/lua/mir4_mep_v0.lua' = $luaBinding.Replace("`r`n","`n")
    'sdk/preview/mir4/reference/target-providers.json' = (ConvertTo-MIR4PlatformCanonicalJson ([ordered]@{schema=0;kind='MIR4TargetProviderSetV0';providers=$providers})) + "`n"
    'sdk/preview/mir4/reference/affected-target-plan.json' = (ConvertTo-MIR4PlatformCanonicalJson $affectedTargets) + "`n"
    'sdk/preview/mir4/reference/compilation-runs.json' = (ConvertTo-MIR4PlatformCanonicalJson ([ordered]@{schema=0;kind='MIR4CompilationRunSetV0';runs=$runs})) + "`n"
    'sdk/preview/mir4/reference/runtime-state-inventory.json' = (ConvertTo-MIR4PlatformCanonicalJson $runtime) + "`n"
    'sdk/preview/mir4/reference/process-ir-inventory.json' = (ConvertTo-MIR4PlatformCanonicalJson $process) + "`n"
    'sdk/preview/mir4/reference/opportunity-catalogue.json' = (ConvertTo-MIR4PlatformCanonicalJson $opportunities) + "`n"
    'sdk/preview/mir4/reference/release-dag.json' = (ConvertTo-MIR4PlatformCanonicalJson $releaseDag) + "`n"
    'sdk/preview/mir4/reference/query-snapshot-f210.json' = (ConvertTo-MIR4PlatformCanonicalJson $query) + "`n"
    'sdk/preview/mir4/reference/support-snapshot-f210.json' = (ConvertTo-MIR4PlatformCanonicalJson $support) + "`n"
    'sdk/preview/mir4/reference/shadow-extension-run-f210.json' = (ConvertTo-MIR4PlatformCanonicalJson $shadowExtensionRun) + "`n"
    'sdk/preview/mir4/reference-extension/extension.json' = (ConvertTo-MIR4PlatformCanonicalJson $extension) + "`n"
    'sdk/preview/mir4/reference-extension/README.md' = "# MIR 4 reference extension V0`n`nThis data-only extension exercises all eight MEP V0 fragment kinds and carries no prototype-write capability.`n"
    'sdk/preview/mir4/inspector/index.html' = (Get-MIR4InspectorHtml).Replace("`r`n","`n")
    'sdk/preview/mir4/inspector/Export-MIR4SupportSnapshot.ps1' = $inspectorPs.Replace("`r`n","`n")
    'sdk/preview/mir4/inspector/README.md' = "# MIR 4 Inspector V0`n`nOpen ``index.html`` locally and select a generated JSON snapshot. The browser-only viewer performs no upload and no mutation.`n"
    'sdk/preview/mir4/conformance/Invoke-MIR4SdkConformance.ps1' = $conformancePs.Replace("`r`n","`n")
    'sdk/preview/mir4/README.md' = "# MIR 4 SDK V0 preview`n`nRun ``.\conformance\Invoke-MIR4SdkConformance.ps1`` with PowerShell 7. API bindings are under ``api-v0``; MEP bindings are under ``powershell`` and ``lua``; deterministic examples and shadow reports are under ``reference``. This preview is read-only, package-excluded, and may change before 1.0.`n"
    'fixtures/mir4-mep-v0/positive/reference-extension.json' = (ConvertTo-MIR4PlatformCanonicalJson $extension) + "`n"
    'fixtures/mir4-mep-v0/negative/forbidden-callback.json' = "{`"expected_diagnostic`":`"mir4-mep-forbidden-field`",`"kind`":`"MIR4ExtensionEnvelopeV0`",`"schema`":0,`"extension_id`":`"org.example.bad`",`"targets`":[`"f210`"],`"fragments`":[{`"id`":`"org.example.bad.fragment`",`"kind`":`"CompatibilityFragment`",`"data`":{`"callback`":`"run`"}}],`"canonicalization`":`"mir-canonical-json-v0`",`"digest`":`"sha256:0000000000000000000000000000000000000000000000000000000000000000`"}`n"
    'fixtures/mir4-process-ir-v0/positive/bounded-loop.json' = (ConvertTo-MIR4PlatformCanonicalJson $processSafeFixture) + "`n"
    'fixtures/mir4-process-ir-v0/negative/unbounded-loop.json' = (ConvertTo-MIR4PlatformCanonicalJson $processUnsafeFixture) + "`n"
    'docs/reference/generated/mir4-platform-component-matrix.md' = $generatedDoc
  }
  return $files
}

function Invoke-MIR4PlatformGenerate {
  param([Parameter(Mandatory)][string]$RepoRoot, [switch]$Check)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $files = Get-MIR4PlatformGeneratedFiles $repo
  foreach ($entry in $files.GetEnumerator()) {
    $path = Join-Path $repo $entry.Key
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(([string]$entry.Value).Replace("`r`n","`n"))
    if ($Check) {
      if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not [Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($path),[byte[]]$bytes)) {
        throw "[mir4-platform-stale] $($entry.Key)"
      }
    } else {
      New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
      [IO.File]::WriteAllBytes($path,$bytes)
    }
  }
  return $files.Keys
}

function Test-MIR4PlatformConformance {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  Invoke-MIR4PlatformGenerate -RepoRoot $repo -Check | Out-Null
  . (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
  $sourceBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  $positive = Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/mir4-mep-v0/positive/reference-extension.json') | ConvertFrom-Json
  Test-MIR4MepEnvelope -Envelope $positive -RepoRoot $repo | Out-Null
  $negative = Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/mir4-mep-v0/negative/forbidden-callback.json') | ConvertFrom-Json
  $expected = [string]$negative.expected_diagnostic
  $negative.PSObject.Properties.Remove('expected_diagnostic')
  try { Test-MIR4MepEnvelope -Envelope $negative -RepoRoot $repo | Out-Null; throw '[mir4-mep-negative-accepted] Forbidden callback fixture was accepted.' }
  catch { if (-not $_.Exception.Message.StartsWith("[$expected]")) { throw "[mir4-mep-negative-diagnostic] Expected $expected, got $($_.Exception.Message)" } }
  $sourceAfter = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  if ($sourceBefore -cne $sourceAfter) { throw '[mir4-platform-package-mutation] Platform generation changed player package sources.' }
  $shipped = @(Get-MIRPackageSourceFiles -RepoRoot $repo)
  foreach ($prefix in @('sdk/','spec/','fixtures/','docs/','tools/','.mir/','mir.toml','mir.lock')) {
    if (@($shipped | Where-Object { $_.StartsWith($prefix) -or $_ -eq $prefix.TrimEnd('/') }).Count -gt 0) { throw "[mir4-platform-package-visible] $prefix" }
  }
  $runs = (Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/compilation-runs.json') | ConvertFrom-Json).runs
  if (@($runs | Where-Object { $_.authoritative_output -or $_.mutation_capability }).Count -gt 0) { throw '[mir4-platform-shadow-interference] Shadow run acquired authority or mutation.' }
  if (@($runs | Where-Object { -not $_.feature_manifest -or -not $_.setting_spec -or 'safety-kernel' -notin @($_.stages) -or 'policy-engine' -notin @($_.stages) }).Count -gt 0) { throw '[mir4-platform-normalized-run-incomplete]' }
  $releaseDag = Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/release-dag.json') | ConvertFrom-Json
  Test-MIR4ReleaseDag -Dag $releaseDag | Out-Null
  $accepted = Resolve-MIR4PolicyDisposition -Contribution ([pscustomobject]@{subject='reference-safe';operations=@('read-only-query');evidence=@('fixture:reference-positive');requested_disposition='preserve'})
  if ([string]$accepted.disposition -cne 'preserve' -or $accepted.mutation_authorized -or -not $accepted.review_required) { throw '[mir4-policy-safe-disposition]' }
  $rejected = Resolve-MIR4PolicyDisposition -Contribution ([pscustomobject]@{subject='reference-unsafe';operations=@('prototype-write');evidence=@('fixture:reference-negative');requested_disposition='handle'})
  if ([string]$rejected.disposition -cne 'fail-hard-safety' -or $rejected.mutation_authorized -or $rejected.safety.hard_safety_overridable) { throw '[mir4-policy-hard-safety-override]' }
  foreach ($fixturePath in @('fixtures/mir4-process-ir-v0/positive/bounded-loop.json','fixtures/mir4-process-ir-v0/negative/unbounded-loop.json')) {
    $fixture = Get-Content -Raw -LiteralPath (Join-Path $repo $fixturePath) | ConvertFrom-Json
    $decision = Resolve-MIR4PolicyDisposition -Contribution $fixture.contribution
    if ([string]$decision.safety.status -cne [string]$fixture.expected_status) { throw "[mir4-process-ir-fixture-status] $fixturePath" }
    if ($fixture.expected_violation -and [string]$fixture.expected_violation -notin @($decision.safety.violations)) { throw "[mir4-process-ir-fixture-violation] $fixturePath" }
  }
  return $true
}

function Write-MIR4DeterministicPreviewArchive {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][string]$RootName,[Parameter(Mandatory)][string[]]$RelativePaths)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  New-Item -ItemType Directory -Force -Path (Split-Path $OutputPath -Parent) | Out-Null
  Add-Type -AssemblyName System.IO.Compression
  $stream = [IO.File]::Open($OutputPath,[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try {
    $zip = [IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
    try {
      $rows = @()
      foreach ($relative in @($RelativePaths | Sort-Object -Unique)) {
        $path = Join-Path $repo $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-preview-package-input] Missing $relative" }
        $bytes = [IO.File]::ReadAllBytes($path)
        $rows += [ordered]@{path=$relative.Replace('\','/');bytes=$bytes.Length;sha256=(Get-MIR4PlatformFileSha256 $path)}
        $entry = $zip.CreateEntry(($RootName + '/' + $relative.Replace('\','/')),[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
        $entryStream = $entry.Open(); try { $entryStream.Write($bytes,0,$bytes.Length) } finally { $entryStream.Dispose() }
      }
      $manifestObject = [pscustomobject][ordered]@{schema=0;kind='MIR4PreviewAssetManifestV0';root=$RootName;source_version='4.0.0';candidate_wave='M4C01';files=$rows;digest=''}
      Add-MIR4PlatformDigest $manifestObject | Out-Null
      $manifestBytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4PlatformCanonicalJson $manifestObject)+"`n")
      $manifestEntry = $zip.CreateEntry(($RootName + '/manifest.json'),[IO.Compression.CompressionLevel]::Optimal)
      $manifestEntry.LastWriteTime = [DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
      $manifestStream = $manifestEntry.Open(); try { $manifestStream.Write($manifestBytes,0,$manifestBytes.Length) } finally { $manifestStream.Dispose() }
    } finally { $zip.Dispose() }
  } finally { $stream.Dispose() }
}

function New-MIR4PlatformPreviewPackages {
  param([Parameter(Mandatory)][string]$RepoRoot,[string]$OutputRoot='build/mir4/platform-preview')
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  Invoke-MIR4PlatformGenerate -RepoRoot $repo -Check | Out-Null
  Test-MIR4PlatformConformance -RepoRoot $repo | Out-Null
  $output = if ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot)) }
  $allowedOutput = [IO.Path]::GetFullPath((Join-Path $repo 'build')).TrimEnd('\') + '\'
  if (-not ($output + '\').StartsWith($allowedOutput,[StringComparison]::OrdinalIgnoreCase)) { throw "[mir4-preview-output-boundary] $output" }
  $allSdk = @(Get-ChildItem -LiteralPath (Join-Path $repo 'sdk/preview/mir4') -Recurse -File) | ForEach-Object { [IO.Path]::GetRelativePath($repo,$_.FullName).Replace('\','/') }
  $sets = [ordered]@{
    'mir4-sdk-v0-preview.zip' = @($allSdk + @('spec/api/mir4-v0/contracts.json','spec/schemas/preview/mir4-mep-v0.schema.json','docs/reference/generated/mir4-experimental-api-v0.md','docs/reference/mir4-mep-v0.md','docs/reference/mir4-sdk-v0-quickstart.md','docs/reference/mir4-api-sdk-v0-stability.md','LICENSE'))
    'mir4-platform-preview-v0.zip' = @('mir.toml','mir.lock','spec/platform/mir4-preview-v0/platform.json','spec/platform/mir4-preview-v0/release-dag.json','docs/architecture/mir4-platform-preview.md','docs/reference/generated/mir4-platform-component-matrix.md','sdk/preview/mir4/reference/target-providers.json','sdk/preview/mir4/reference/affected-target-plan.json','sdk/preview/mir4/reference/compilation-runs.json','sdk/preview/mir4/reference/runtime-state-inventory.json','sdk/preview/mir4/reference/process-ir-inventory.json','sdk/preview/mir4/reference/opportunity-catalogue.json','sdk/preview/mir4/reference/release-dag.json','sdk/preview/mir4/reference/shadow-extension-run-f210.json','fixtures/mir4-process-ir-v0/positive/bounded-loop.json','fixtures/mir4-process-ir-v0/negative/unbounded-loop.json','tools/lib/mir4/SafetyKernel.ps1','tools/lib/mir4/PolicyEngine.ps1','tools/lib/mir4/NormalizedCompiler.ps1','tools/lib/mir4/RuntimeStateModel.ps1','tools/lib/mir4/ProcessIR.ps1','tools/lib/mir4/ReleaseDag.ps1','LICENSE')
    'mir4-reference-extension-v0.zip' = @('sdk/preview/mir4/reference-extension/extension.json','sdk/preview/mir4/reference-extension/README.md','spec/schemas/preview/mir4-mep-v0.schema.json','LICENSE')
    'mir4-inspector-preview-v0.zip' = @('sdk/preview/mir4/inspector/index.html','sdk/preview/mir4/inspector/Export-MIR4SupportSnapshot.ps1','sdk/preview/mir4/inspector/README.md','sdk/preview/mir4/reference/query-snapshot-f210.json','sdk/preview/mir4/reference/support-snapshot-f210.json','LICENSE')
  }
  $hashes = @()
  foreach ($set in $sets.GetEnumerator()) {
    $path = Join-Path $output $set.Key
    Write-MIR4DeterministicPreviewArchive -RepoRoot $repo -OutputPath $path -RootName ([IO.Path]::GetFileNameWithoutExtension($set.Key)) -RelativePaths @($set.Value)
    $hashes += [ordered]@{name=$set.Key;bytes=(Get-Item -LiteralPath $path).Length;sha256=(Get-MIR4PlatformFileSha256 $path)}
  }
  $manifest = [pscustomobject][ordered]@{schema=0;kind='MIR4PreviewAssetSetV0';source_version='4.0.0';candidate_wave='M4C01';assets=$hashes;publication='github-preview-only-not-mod-portal';digest=''}
  Add-MIR4PlatformDigest $manifest | Out-Null
  [IO.File]::WriteAllText((Join-Path $output 'preview-assets.json'),(ConvertTo-MIR4PlatformCanonicalJson $manifest)+"`n",[Text.UTF8Encoding]::new($false))
  return $manifest
}
