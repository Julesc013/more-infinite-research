$script:MIR4ApiKinds = @(
  'MIR4HostManifestV0',
  'MIR4ExtensionEnvelopeV0',
  'MIR4QuerySnapshotV0',
  'MIR4ProfileV0',
  'MIR4DiagnosticV0',
  'MIR4SupportSnapshotV0'
)
function ConvertTo-MIR4ApiCanonicalValue($Value){
  if ($null -eq $Value) { return $null }
  if ($Value -is [string] -or $Value -is [bool] -or $Value -is [ValueType]) { return $Value }
  if ($Value -is [Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)) {
      $result[$key] = ConvertTo-MIR4ApiCanonicalValue $Value[$key]
    }
    return $result
  }
  if ($Value -is [pscustomobject]) {
    $result = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Sort-Object Name -CaseSensitive)) {
      $result[$property.Name] = ConvertTo-MIR4ApiCanonicalValue $property.Value
    }
    return $result
  }
  if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    Write-Output -NoEnumerate @($Value | ForEach-Object { ConvertTo-MIR4ApiCanonicalValue $_ })
    return
  }
  return $Value
}
function ConvertTo-MIR4ApiCanonicalJson {
  param([Parameter(Mandatory)]$Value)
  (ConvertTo-MIR4ApiCanonicalValue $Value) | ConvertTo-Json -Depth 50 -Compress
}
function Get-MIR4ApiDigest {
  param([Parameter(Mandatory)]$Value)
  $material = [ordered]@{}
  foreach ($property in $Value.PSObject.Properties) {
    if ($property.Name -ne 'digest') { $material[$property.Name] = $property.Value }
  }
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4ApiCanonicalJson $material))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return 'sha256:' + ([BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()) }
  finally { $sha.Dispose() }
}
function New-MIR4ApiRecord {
  param(
    [Parameter(Mandatory)][ValidateSet('MIR4HostManifestV0','MIR4ExtensionEnvelopeV0','MIR4QuerySnapshotV0','MIR4ProfileV0','MIR4DiagnosticV0','MIR4SupportSnapshotV0')][string]$Kind,
    [Parameter(Mandatory)][string]$TargetId,
    [Parameter(Mandatory)][string]$FactorioLine,
    [Parameter(Mandatory)][string]$SourceVersion,
    [Parameter(Mandatory)][string]$DistributionVersion,
    [string[]]$Capabilities = @(),
    [hashtable]$Extensions = @{},
    $Payload = [ordered]@{}
  )
  $record = [pscustomobject][ordered]@{
    kind = $Kind
    schema = 0
    target = [ordered]@{ id=$TargetId; factorio_line=$FactorioLine; transport='build-time-static' }
    versions = [ordered]@{ source=$SourceVersion; distribution=$DistributionVersion }
    capabilities = @($Capabilities | Sort-Object -Unique)
    canonicalization = 'mir-canonical-json-v0'
    extensions = $Extensions
    payload = $Payload
    digest = ''
  }
  $record.digest = Get-MIR4ApiDigest $record
  return $record
}
function Test-MIR4ApiRecord {
  param([Parameter(Mandatory)]$Record, [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path)
  if ([string]$Record.kind -notin $script:MIR4ApiKinds) { throw '[mir4-api-kind] Unknown preview contract kind.' }
  $schemaPath = Join-Path $RepoRoot "spec\schemas\experimental\$(([string]$Record.kind).ToLowerInvariant()).schema.json"
  try { $valid = (($Record | ConvertTo-Json -Depth 50) | Test-Json -SchemaFile $schemaPath -ErrorAction Stop) }
  catch { throw '[mir4-api-schema] Contract schema validation failed.' }
  if (-not $valid) { throw '[mir4-api-schema] Contract schema validation failed.' }
  foreach ($namespace in @($Record.extensions.PSObject.Properties.Name | Where-Object { $_ })) {
    if ($namespace -notmatch '^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$') { throw '[mir4-api-namespace] Invalid extension namespace.' }
  }
  if ([string]$Record.digest -cne (Get-MIR4ApiDigest $Record)) { throw '[mir4-api-digest] Contract digest mismatch.' }
  return $true
}
function Get-MIR4ApiSchema([string]$Kind,[string]$Description){[ordered]@{'$schema'='https://json-schema.org/draft/2020-12/schema';'$id'="https://mir.invalid/preview/api-v0/$($Kind.ToLowerInvariant()).schema.json";'x-mir-canonical-path'="spec/schemas/experimental/$($Kind.ToLowerInvariant()).schema.json";title="$Kind (developer preview)";description=$Description;type='object';additionalProperties=$false;required=@('kind','schema','target','versions','capabilities','canonicalization','extensions','payload','digest');properties=[ordered]@{kind=@{const=$Kind};schema=@{const=0};target=@{type='object';additionalProperties=$false;required=@('id','factorio_line','transport');properties=@{id=@{type='string';pattern='^f[0-9]{3}$'};factorio_line=@{type='string';pattern='^[0-9]+\.[0-9]+$'};transport=@{enum=@('build-time-static','stage-local-read-only','prototype-stage-read-only','mod-data-read-only')}}};versions=@{type='object';additionalProperties=$false;required=@('source','distribution');properties=@{source=@{type='string';minLength=1;maxLength=64};distribution=@{type='string';minLength=1;maxLength=64}}};capabilities=@{type='array';maxItems=128;uniqueItems=$true;items=@{type='string';pattern='^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$'}};canonicalization=@{const='mir-canonical-json-v0'};extensions=@{type='object';maxProperties=32;propertyNames=@{pattern='^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$'};additionalProperties=$true};payload=@{type='object';maxProperties=128;additionalProperties=$true};digest=@{type='string';pattern='^sha256:[0-9a-f]{64}$'}}}}
function Invoke-MIR4SdkGenerateV0{param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
 $a=Get-Content -Raw(Join-Path $RepoRoot 'spec\api\mir4-v0\contracts.json')|ConvertFrom-Json;$out=[ordered]@{};$defs=[ordered]@{};foreach($c in $a.contracts){$s=Get-MIR4ApiSchema $c.kind $c.description;$defs[$c.kind]=$s;$out["spec/schemas/experimental/$(([string]$c.kind).ToLowerInvariant()).schema.json"]=(ConvertTo-MIR4ApiCanonicalJson $s)+"`n"};$bundle=[ordered]@{'$schema'='https://json-schema.org/draft/2020-12/schema';'$id'='https://mir.invalid/preview/api-v0/mir4-api-v0.bundle.schema.json';title='MIR 4 API V0 developer-preview schema bundle';'$defs'=$defs};$out['sdk/experimental/mir4/json-schema/mir4-api-v0.bundle.schema.json']=(ConvertTo-MIR4ApiCanonicalJson $bundle)+"`n"
 $out['sdk/experimental/mir4/powershell/MIR4.Api.V0.psm1']=@'
# Generated standalone developer-preview package-excluded binding.
$script:MIR4ApiKinds=@('MIR4HostManifestV0','MIR4ExtensionEnvelopeV0','MIR4QuerySnapshotV0','MIR4ProfileV0','MIR4DiagnosticV0','MIR4SupportSnapshotV0')
function ConvertTo-MIR4ApiCanonicalValue($Value){
  if($null-eq$Value){return $null}
  if($Value-is[string]-or$Value-is[bool]-or$Value-is[ValueType]){return $Value}
  if($Value-is[Collections.IDictionary]){$result=[ordered]@{};foreach($key in @($Value.Keys|ForEach-Object{[string]$_}|Sort-Object -CaseSensitive)){$result[$key]=ConvertTo-MIR4ApiCanonicalValue $Value[$key]};return $result}
  if($Value-is[pscustomobject]){$result=[ordered]@{};foreach($property in @($Value.PSObject.Properties|Sort-Object Name -CaseSensitive)){$result[$property.Name]=ConvertTo-MIR4ApiCanonicalValue $property.Value};return $result}
  if($Value-is[Collections.IEnumerable]-and$Value-isnot[string]){Write-Output -NoEnumerate @($Value|ForEach-Object{ConvertTo-MIR4ApiCanonicalValue $_});return}
  return $Value
}
function ConvertTo-MIR4ApiCanonicalJson{param([Parameter(Mandatory)]$Value)(ConvertTo-MIR4ApiCanonicalValue $Value)|ConvertTo-Json -Depth 50 -Compress}
function Get-MIR4ApiDigest{param([Parameter(Mandatory)]$Value)$material=[ordered]@{};foreach($property in $Value.PSObject.Properties){if($property.Name-ne'digest'){$material[$property.Name]=$property.Value}};$bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4ApiCanonicalJson $material));$sha=[Security.Cryptography.SHA256]::Create();try{'sha256:'+([BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant())}finally{$sha.Dispose()}}
function New-MIR4ApiRecord{
  param([Parameter(Mandatory)][ValidateSet('MIR4HostManifestV0','MIR4ExtensionEnvelopeV0','MIR4QuerySnapshotV0','MIR4ProfileV0','MIR4DiagnosticV0','MIR4SupportSnapshotV0')][string]$Kind,[Parameter(Mandatory)][string]$TargetId,[Parameter(Mandatory)][string]$FactorioLine,[Parameter(Mandatory)][string]$SourceVersion,[Parameter(Mandatory)][string]$DistributionVersion,[string[]]$Capabilities=@(),[hashtable]$Extensions=@{},$Payload=[ordered]@{})
  $record=[pscustomobject][ordered]@{kind=$Kind;schema=0;target=[ordered]@{id=$TargetId;factorio_line=$FactorioLine;transport='build-time-static'};versions=[ordered]@{source=$SourceVersion;distribution=$DistributionVersion};capabilities=@($Capabilities|Sort-Object -Unique);canonicalization='mir-canonical-json-v0';extensions=$Extensions;payload=$Payload;digest=''}
  $record.digest=Get-MIR4ApiDigest $record
  return $record
}
function Test-MIR4ApiRecord{
  param([Parameter(Mandatory)]$Record,[string]$RepoRoot='')
  if([string]$Record.kind-notin$script:MIR4ApiKinds){throw '[mir4-api-kind] Unknown preview contract kind.'}
  $schemaPath=$null
  if($RepoRoot){$candidate=Join-Path $RepoRoot "spec/schemas/experimental/$(([string]$Record.kind).ToLowerInvariant()).schema.json";if(Test-Path -LiteralPath $candidate -PathType Leaf){$schemaPath=$candidate}}
  try{
    if($schemaPath){$valid=(($Record|ConvertTo-Json -Depth 50)|Test-Json -SchemaFile $schemaPath -ErrorAction Stop)}
    else{$bundlePath=Join-Path $PSScriptRoot '../json-schema/mir4-api-v0.bundle.schema.json';$bundle=Get-Content -Raw -LiteralPath $bundlePath|ConvertFrom-Json;$schema=$bundle.'$defs'.([string]$Record.kind)|ConvertTo-Json -Depth 50 -Compress;$valid=(($Record|ConvertTo-Json -Depth 50)|Test-Json -Schema $schema -ErrorAction Stop)}
  }catch{throw '[mir4-api-schema] Contract schema validation failed.'}
  if(-not$valid){throw '[mir4-api-schema] Contract schema validation failed.'}
  foreach($namespace in @($Record.extensions.PSObject.Properties.Name|Where-Object{$_})){if($namespace-notmatch'^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$'){throw '[mir4-api-namespace] Invalid extension namespace.'}}
  if([string]$Record.digest-cne(Get-MIR4ApiDigest $Record)){throw '[mir4-api-digest] Contract digest mismatch.'}
  return $true
}
Export-ModuleMember -Function New-MIR4ApiRecord,Test-MIR4ApiRecord,ConvertTo-MIR4ApiCanonicalJson,Get-MIR4ApiDigest
'@
 $out['sdk/experimental/mir4/lua/mir4_api_v0.lua']=@'
-- Generated developer-preview package-excluded binding.
local M = {}
local kinds = {MIR4HostManifestV0=true,MIR4ExtensionEnvelopeV0=true,MIR4QuerySnapshotV0=true,MIR4ProfileV0=true,MIR4DiagnosticV0=true,MIR4SupportSnapshotV0=true}
local transports = {['build-time-static']=true,['stage-local-read-only']=true,['prototype-stage-read-only']=true,['mod-data-read-only']=true}

local function valid_capability(value)
  if type(value) ~= 'string' or not string.match(value, '^[a-z][a-z0-9%.%-]*$') then return false end
  return not string.match(value, '[%.%-][%.%-]') and not string.match(value, '[%.%-]$')
end

local function valid_namespace(value)
  if type(value) ~= 'string' or not string.find(value, '.', 1, true) then return false end
  local count = 0
  for part in string.gmatch(value, '[^%.]+') do
    count = count + 1
    if not string.match(part, '^[a-z][a-z0-9%-]*$') then return false end
  end
  return count >= 2 and not string.match(value, '%.%.') and not string.match(value, '%.$')
end

function M.validate(v)
  if type(v) ~= 'table' or not kinds[v.kind] then return nil, 'mir4-api-kind' end
  if v.schema ~= 0 or type(v.target) ~= 'table' or type(v.versions) ~= 'table' or type(v.payload) ~= 'table' then return nil, 'mir4-api-schema' end
  if type(v.target.id) ~= 'string' or not string.match(v.target.id, '^f%d%d%d$') or type(v.target.factorio_line) ~= 'string' or not string.match(v.target.factorio_line, '^%d+%.%d+$') or not transports[v.target.transport] then return nil, 'mir4-api-schema' end
  if type(v.versions.source) ~= 'string' or #v.versions.source < 1 or #v.versions.source > 64 or type(v.versions.distribution) ~= 'string' or #v.versions.distribution < 1 or #v.versions.distribution > 64 then return nil, 'mir4-api-schema' end
  if type(v.capabilities) ~= 'table' then return nil, 'mir4-api-schema' end
  if #v.capabilities > 128 then return nil, 'mir4-api-cardinality' end
  local seen = {}
  for _, capability in ipairs(v.capabilities) do
    if not valid_capability(capability) or seen[capability] then return nil, 'mir4-api-schema' end
    seen[capability] = true
  end
  if v.canonicalization ~= 'mir-canonical-json-v0' then return nil, 'mir4-api-canonicalization' end
  if type(v.extensions) ~= 'table' then return nil, 'mir4-api-schema' end
  local extension_count = 0
  for namespace in pairs(v.extensions) do
    extension_count = extension_count + 1
    if not valid_namespace(namespace) then return nil, 'mir4-api-namespace' end
  end
  if extension_count > 32 then return nil, 'mir4-api-cardinality' end
  if type(v.digest) ~= 'string' or not string.match(v.digest, '^sha256:[0-9a-f]+$') or #v.digest ~= 71 then return nil, 'mir4-api-digest' end
  return true
end

function M.build(v)
  local ok, error_code = M.validate(v)
  if not ok then return nil, error_code end
  return v
end
return M
'@
 $out['sdk/preview/mir4/api-v0/json-schema/mir4-api-v0.bundle.schema.json']=$out['sdk/experimental/mir4/json-schema/mir4-api-v0.bundle.schema.json']
 $out['sdk/preview/mir4/api-v0/powershell/MIR4.Api.V0.psm1']=$out['sdk/experimental/mir4/powershell/MIR4.Api.V0.psm1']
 $out['sdk/preview/mir4/api-v0/lua/mir4_api_v0.lua']=$out['sdk/experimental/mir4/lua/mir4_api_v0.lua']
 $rows=@($a.contracts|%{"| ``$($_.kind)`` | $($_.description) |"});$out['docs/reference/generated/mir4-experimental-api-v0.md']="---`ntitle: `"MIR 4 API/SDK V0 Preview`"`nstatus: current`napplies_to: `"4.0 developer preview`"`naudience: developer`ndoc_type: reference`nowner: mir-maintainers`nlast_reviewed: 2026-08-18`nsupersedes: []`nsuperseded_by: []`n---`n# MIR 4 API/SDK V0 Preview`n`nGenerated from ``spec/api/mir4-v0/contracts.json``. This is real, package-excluded, read-only developer-preview tooling. Compatibility may change before 1.0 and it does not establish a player support claim.`n`n## Quickstart`n`n- ``.\tools\mir.ps1 mir4 sdk generate```n- ``.\tools\mir.ps1 mir4 sdk check```n- ``.\tools\mir.ps1 mir4 api check```n- ``.\tools\mir.ps1 mir4 api conformance```n- ``.\tools\mir.ps1 mir4 platform conformance```n- ``.\tools\mir.ps1 mir4 platform package```n`n| Kind | Purpose |`n| --- | --- |`n$($rows-join"`n")`n`nCanonical JSON recursively sorts object keys, preserves array order, uses compact UTF-8, and hashes the record with ``digest`` omitted. Unknown top-level fields, invalid reverse-DNS namespaces, more than 128 capabilities, more than 32 extensions, and digest mismatch fail closed.`n`nTarget transports are read-only. Mutable compiler context, executors, SafetyKernel internals, and prototype emission are never exposed. MEP V0, the reference extension, Inspector, target-provider projections, shadow compilation runs, Runtime/State inventory, and ProcessIR reports are distributed as separate preview assets.`n"
 foreach($e in $out.GetEnumerator()){$p=Join-Path $RepoRoot $e.Key;$b=[Text.UTF8Encoding]::new($false).GetBytes(([string]$e.Value).Replace("`r`n","`n"));if($Check){if(-not(Test-Path $p)-or-not[Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($p),[byte[]]$b)){throw "[mir4-sdk-stale] $($e.Key)"}}else{New-Item -ItemType Directory -Force(Split-Path $p -Parent)|Out-Null;[IO.File]::WriteAllBytes($p,$b)}}
}

function Get-MIR4ModuleEcosystemSdkFiles {
  param([Parameter(Mandatory)][string]$RepoRoot)
  . (Join-Path $RepoRoot 'tools/lib/mir4/ModuleEcosystem.ps1')
  $authority = Get-MIR4ModuleEcosystemAuthority -RepoRoot $RepoRoot
  $mepSchema = Get-MIR4MepV1Schema -Authority $authority
  $apiSchema = Get-MIR4ApiV1Schema -Authority $authority
  $reference = New-MIR4ReferenceExtensionV1 -RepoRoot $RepoRoot
  $closure = Resolve-MIR4ExtensionClosureV1 -RepoRoot $RepoRoot -Extensions @($reference) -Target f210
  $transport = New-MIR4TargetTransportPlanV1 -RepoRoot $RepoRoot
  $apiAvailable = New-MIR4ApiV1Response -RepoRoot $RepoRoot -Surface query -Target f210 -Items @([ordered]@{id='alpha';status='known'},[ordered]@{id='beta';status='known'}) -Limit 1 -Evidence @('vector:available')
  $apiUnavailable = New-MIR4ApiV1Response -RepoRoot $RepoRoot -Surface observation -Target f012 -Availability unavailable -Reason 'The museum target has no admitted observation transport.' -Evidence @('target:f012','admission:BLOCKED_WITH_EVIDENCE')
  $forbidden = (($reference | ConvertTo-Json -Depth 100) | ConvertFrom-Json)
  $forbidden.fragments[0].data | Add-Member -NotePropertyName callback -NotePropertyValue 'forbidden'
  $missing = (($reference | ConvertTo-Json -Depth 100) | ConvertFrom-Json)
  $missing.extension_id='org.example.missing';$missing.namespace='org.example.missing';$missing.fragments[5].data.extension_id='org.example.not-installed';$missing.digest='';$missing.digest=Get-MIR4ModuleDigest $missing
  $cycleA = (($reference | ConvertTo-Json -Depth 100) | ConvertFrom-Json);$cycleA.extension_id='org.example.cycle-a';$cycleA.namespace='org.example.cycle-a';$cycleA.fragments[5].data.extension_id='org.example.cycle-b';$cycleA.digest='';$cycleA.digest=Get-MIR4ModuleDigest $cycleA
  $cycleB = (($reference | ConvertTo-Json -Depth 100) | ConvertFrom-Json);$cycleB.extension_id='org.example.cycle-b';$cycleB.namespace='org.example.cycle-b';$cycleB.fragments[5].data.extension_id='org.example.cycle-a';$cycleB.digest='';$cycleB.digest=Get-MIR4ModuleDigest $cycleB
  $files = [ordered]@{}
  $files['spec/schemas/preview/mir4-mep-v1.schema.json'] = (ConvertTo-MIR4ModuleCanonicalJson $mepSchema)+"`n"
  $files['spec/schemas/preview/mir4-api-v1-response.schema.json'] = (ConvertTo-MIR4ModuleCanonicalJson $apiSchema)+"`n"
  $files['sdk/preview/mir4/mep-v1/json-schema/mir4-mep-v1.schema.json'] = $files['spec/schemas/preview/mir4-mep-v1.schema.json']
  $files['sdk/preview/mir4/api-v1/json-schema/mir4-api-v1-response.schema.json'] = $files['spec/schemas/preview/mir4-api-v1-response.schema.json']
  $files['sdk/preview/mir4/mep-v1/lua/mir4_mep_v1.lua'] = @'
-- Generated package-excluded MIR Extension Protocol V1 preview helper.
local M = {}
local fragment_kinds = {
  CompatibilityFragment=true,ProfileFragment=true,ProofFragment=true,PresentationFragment=true,
  CapabilityRequirement=true,ExtensionDependency=true,ExtensionConflict=true,FinalizationRequirement=true,
  ProcessClassificationFragment=true,MigrationFragment=true,TargetDispositionFragment=true,ExternalEffectChannelDeclaration=true
}
local forbidden = {callback=true,callbacks=true,compiler_context=true,data_raw=true,executor=true,prototype=true,prototype_write=true,safety_kernel=true,safety_kernel_override=true}
local function scan(value)
  if type(value) ~= 'table' then return true end
  for key, child in pairs(value) do
    if forbidden[key] then return nil, 'mir4-mep-v1-forbidden-field' end
    local ok, err = scan(child); if not ok then return nil, err end
  end
  return true
end
function M.validate(value)
  if type(value) ~= 'table' or value.kind ~= 'MIR4ExtensionEnvelopeV1' or value.schema ~= 1 then return nil, 'mir4-mep-v1-schema' end
  if type(value.extension_id) ~= 'string' or type(value.extension_version) ~= 'string' or type(value.namespace) ~= 'string' then return nil, 'mir4-mep-v1-schema' end
  if type(value.targets) ~= 'table' or #value.targets < 1 or #value.targets > 17 or type(value.fragments) ~= 'table' or #value.fragments < 1 or #value.fragments > 64 then return nil, 'mir4-mep-v1-cardinality' end
  local ids = {}
  for _, fragment in ipairs(value.fragments) do
    if type(fragment) ~= 'table' or not fragment_kinds[fragment.kind] or ids[fragment.id] then return nil, 'mir4-mep-v1-fragment' end
    ids[fragment.id] = true
  end
  return scan(value)
end
function M.build(value) local ok, err=M.validate(value);if not ok then return nil,err end;return value end
return M
'@
  $files['sdk/preview/mir4/mep-v1/lua/mir4_mep_v1.luals.lua'] = @'
---@class MIR4FragmentV1
---@field id string
---@field kind 'CompatibilityFragment'|'ProfileFragment'|'ProofFragment'|'PresentationFragment'|'CapabilityRequirement'|'ExtensionDependency'|'ExtensionConflict'|'FinalizationRequirement'|'ProcessClassificationFragment'|'MigrationFragment'|'TargetDispositionFragment'|'ExternalEffectChannelDeclaration'
---@field data table
---@class MIR4ExtensionEnvelopeV1
---@field kind 'MIR4ExtensionEnvelopeV1'
---@field schema 1
---@field extension_id string
---@field extension_version string
---@field namespace string
---@field targets string[]
---@field fragments MIR4FragmentV1[]
---@field canonicalization 'mir-canonical-json-v0'
---@field digest string
'@
  $files['sdk/preview/mir4/api-v1/typescript/index.ts'] = @'
export type Availability = {status: "available" | "unavailable"; reason: string; evidence: string[]};
export type ApiSurface = "host-manifest"|"query"|"profile"|"observation"|"tooling"|"target-provider-abi"|"proof"|"release"|"continuity-bundle";
export interface Mir4ApiResponse<T=unknown>{kind:"MIR4ApiResponseV1";schema:1;surface:ApiSurface;target:{id:string;factorio_line:string;transport:string};versions:{source:string;distribution:string};capabilities:string[];availability:Availability;page:{offset:number;limit:number;returned:number;total:number|null;next_cursor:string|null};items:T[];canonicalization:"mir-canonical-json-v0";extensions:Record<string,unknown>;source_identity:unknown;package_visible:false;mutation_authorized:false;public_support_claim:false;digest:string}
export function unavailable(response:Mir4ApiResponse):boolean{return response.availability.status === "unavailable"}
'@
  $files['sdk/preview/mir4/api-v1/python/mir4_api_v1.py'] = @'
"""Generated package-excluded MIR 4 API V1 preview types."""
from dataclasses import dataclass
from typing import Any, Generic, Optional, TypeVar
T = TypeVar("T")
@dataclass(frozen=True)
class Availability:
    status: str
    reason: str
    evidence: tuple[str, ...]
@dataclass(frozen=True)
class Page(Generic[T]):
    items: tuple[T, ...]
    offset: int
    limit: int
    total: Optional[int]
    next_cursor: Optional[str]
def require_explicit_availability(value: dict[str, Any]) -> None:
    status = value.get("availability", {}).get("status")
    if status not in ("available", "unavailable"):
        raise ValueError("mir4-api-v1-availability")
    if status == "unavailable" and value.get("page", {}).get("total") is not None:
        raise ValueError("mir4-api-v1-unavailable-is-not-zero")
'@
  $files['sdk/preview/mir4/api-v1/powershell/MIR4.Api.V1.psm1'] = @'
# Generated package-excluded MIR 4 API V1 preview helpers.
function Test-MIR4ApiV1Availability {
  param([Parameter(Mandatory)]$Response)
  if([string]$Response.availability.status -notin @('available','unavailable')){throw '[mir4-api-v1-availability]'}
  if([string]$Response.availability.status -eq 'unavailable' -and $null -ne $Response.page.total){throw '[mir4-api-v1-unavailable-is-not-zero]'}
  return $true
}
function Copy-MIR4ApiV1Data { param([AllowNull()]$Value) if($null-eq$Value){return $null};return (($Value|ConvertTo-Json -Depth 100 -Compress)|ConvertFrom-Json) }
Export-ModuleMember -Function Test-MIR4ApiV1Availability,Copy-MIR4ApiV1Data
'@
  $files['sdk/preview/mir4/mep-v1/migration/Convert-MIR4MepV0ToV1.ps1'] = @'
param([Parameter(Mandatory)][string]$InputPath,[Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][string]$RepoRoot)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/ModuleEcosystem.ps1')
$value=Get-Content -Raw -LiteralPath $InputPath|ConvertFrom-Json
$result=ConvertFrom-MIR4MepV0ToV1 -Envelope $value
Test-MIR4MepV1Envelope -Envelope $result -RepoRoot $RepoRoot|Out-Null
[IO.File]::WriteAllText($OutputPath,(ConvertTo-MIR4ModuleCanonicalJson $result)+"`n",[Text.UTF8Encoding]::new($false))
'@
  $files['sdk/preview/mir4/mep-v1/migration/migrate_v0_to_v1.lua'] = @'
-- V0 to V1 migration is intentionally structural and data-only.
return function(v0)
  assert(v0.kind == 'MIR4ExtensionEnvelopeV0' and v0.schema == 0, 'mir4-mep-migrate-source')
  return {kind='MIR4ExtensionEnvelopeV1',schema=1,extension_id=v0.extension_id,extension_version='0.0.0-migrated',namespace=v0.extension_id,targets=v0.targets,fragments=v0.fragments,canonicalization='mir-canonical-json-v0',digest='RECOMPUTE-WITH-CANONICAL-JSON'}
end
'@
  $files['sdk/preview/mir4/reference-extension-v1/extension.json']=(ConvertTo-MIR4ModuleCanonicalJson $reference)+"`n"
  $files['sdk/preview/mir4/reference-extension-v1/README.md']="# MIR 4 synthetic external reference extension V1`n`nThis package-excluded extension exercises all 12 data-only fragment kinds. It is a conformance fallback, not an independent production consumer or public compatibility claim.`n"
  $files['sdk/preview/mir4/reference/extension-closure-v1.json']=(ConvertTo-MIR4ModuleCanonicalJson $closure)+"`n"
  $files['sdk/preview/mir4/reference/extension-transport-plan-v1.json']=(ConvertTo-MIR4ModuleCanonicalJson $transport)+"`n"
  $files['sdk/preview/mir4/api-v1/vectors/available-page-1.json']=(ConvertTo-MIR4ModuleCanonicalJson $apiAvailable)+"`n"
  $files['sdk/preview/mir4/api-v1/vectors/unavailable-observation-f012.json']=(ConvertTo-MIR4ModuleCanonicalJson $apiUnavailable)+"`n"
  $files['fixtures/mir4-mep-v1/positive/reference-extension.json']=(ConvertTo-MIR4ModuleCanonicalJson $reference)+"`n"
  $files['fixtures/mir4-mep-v1/negative/forbidden-callback.json']=(ConvertTo-MIR4ModuleCanonicalJson $forbidden)+"`n"
  $files['fixtures/mir4-mep-v1/negative/missing-dependency.json']=(ConvertTo-MIR4ModuleCanonicalJson $missing)+"`n"
  $files['fixtures/mir4-mep-v1/negative/cycle-a.json']=(ConvertTo-MIR4ModuleCanonicalJson $cycleA)+"`n"
  $files['fixtures/mir4-mep-v1/negative/cycle-b.json']=(ConvertTo-MIR4ModuleCanonicalJson $cycleB)+"`n"
  $files['sdk/preview/mir4/mep-v1/README.md'] = "# MIR Extension Protocol V1 preview`n`nData-only envelopes contribute 12 typed fragment kinds. They cannot carry callbacks, prototype writes, raw compiler context, executors, or SafetyKernel overrides. Resolve dependencies before inspection and treat capability gaps as review-required.`n"
  $files['docs/reference/generated/mir4-api-sdk-v1.md'] = @'
---
title: "MIR 4 API and SDK V1 Preview"
status: current
applies_to: "4.0 developer preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-23
supersedes: []
superseded_by: []
---
# MIR 4 API and SDK V1 Preview

Generated from `spec/api/mir4-v1/contracts.json` and the W05 module-ecosystem authority. The nine APIs return copied, bounded, paginated, capability-labelled data. Unavailability is an explicit status with a reason and evidence; it is never reported as a numeric zero.

Bindings are provided for JSON Schema, Lua with LuaLS annotations, TypeScript, Python, and PowerShell. The reference extension and fixtures exercise all 12 fragment kinds. Use `tools/mir.ps1 mir4 extension` for init, validate, explain, test, package, and migrate commands.

This is package-excluded developer-preview tooling. `BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER` remains open because no governed exact IR4 consumer closure is local.
'@
  $files['sdk/preview/mir4/mep-v1/conformance.ps1'] = @'
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')
$value=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'sdk/preview/mir4/reference-extension-v1/extension.json')|ConvertFrom-Json
Test-MIR4MepV1Envelope -Envelope $value -RepoRoot $RepoRoot|Out-Null
Resolve-MIR4ExtensionClosureV1 -RepoRoot $RepoRoot -Extensions @($value) -Target f210|Out-Null
[pscustomobject]@{status='passed';maturity='developer-preview';production_consumer='BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER'}|ConvertTo-Json
'@
  return $files
}

function Invoke-MIR4SdkGenerate {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  Invoke-MIR4SdkGenerateV0 -RepoRoot $RepoRoot -Check:$Check
  $files = Get-MIR4ModuleEcosystemSdkFiles -RepoRoot $RepoRoot
  foreach($entry in $files.GetEnumerator()) {
    $path=Join-Path $RepoRoot $entry.Key
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(([string]$entry.Value).Replace("`r`n","`n"))
    if($Check) {
      if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or-not[Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($path),[byte[]]$bytes)){throw "[mir4-sdk-v1-stale] $($entry.Key)"}
    } else {
      New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent)|Out-Null
      [IO.File]::WriteAllBytes($path,$bytes)
    }
  }
}
