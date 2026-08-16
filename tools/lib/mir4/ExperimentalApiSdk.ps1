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
    return @($Value | ForEach-Object { ConvertTo-MIR4ApiCanonicalValue $_ })
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
  if ([string]$Record.kind -notin $script:MIR4ApiKinds) { throw '[mir4-api-kind] Unknown experimental contract kind.' }
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
function Get-MIR4ApiSchema([string]$Kind,[string]$Description){[ordered]@{'$schema'='https://json-schema.org/draft/2020-12/schema';'$id'="https://mir.invalid/experimental/$($Kind.ToLowerInvariant()).schema.json";'x-mir-canonical-path'="spec/schemas/experimental/$($Kind.ToLowerInvariant()).schema.json";title="$Kind (experimental)";description=$Description;type='object';additionalProperties=$false;required=@('kind','schema','target','versions','capabilities','canonicalization','extensions','payload','digest');properties=[ordered]@{kind=@{const=$Kind};schema=@{const=0};target=@{type='object';additionalProperties=$false;required=@('id','factorio_line','transport');properties=@{id=@{type='string';pattern='^f[0-9]{3}$'};factorio_line=@{type='string';pattern='^[0-9]+\.[0-9]+$'};transport=@{enum=@('build-time-static','stage-local-read-only','prototype-stage-read-only','mod-data-read-only')}}};versions=@{type='object';additionalProperties=$false;required=@('source','distribution');properties=@{source=@{type='string';minLength=1;maxLength=64};distribution=@{type='string';minLength=1;maxLength=64}}};capabilities=@{type='array';maxItems=128;uniqueItems=$true;items=@{type='string';pattern='^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$'}};canonicalization=@{const='mir-canonical-json-v0'};extensions=@{type='object';maxProperties=32;propertyNames=@{pattern='^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$'};additionalProperties=$true};payload=@{type='object';maxProperties=128;additionalProperties=$true};digest=@{type='string';pattern='^sha256:[0-9a-f]{64}$'}}}}
function Invoke-MIR4SdkGenerate{param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
 $a=Get-Content -Raw(Join-Path $RepoRoot 'spec\api\mir4-v0\contracts.json')|ConvertFrom-Json;$out=[ordered]@{};$defs=[ordered]@{};foreach($c in $a.contracts){$s=Get-MIR4ApiSchema $c.kind $c.description;$defs[$c.kind]=$s;$out["spec/schemas/experimental/$(([string]$c.kind).ToLowerInvariant()).schema.json"]=(ConvertTo-MIR4ApiCanonicalJson $s)+"`n"};$bundle=[ordered]@{'$schema'='https://json-schema.org/draft/2020-12/schema';'$id'='https://mir.invalid/experimental/mir4-api-v0.bundle.schema.json';title='MIR 4 experimental API V0 schema bundle';'$defs'=$defs};$out['sdk/experimental/mir4/json-schema/mir4-api-v0.bundle.schema.json']=(ConvertTo-MIR4ApiCanonicalJson $bundle)+"`n"
 $out['sdk/experimental/mir4/powershell/MIR4.Api.V0.psm1']="# Generated experimental package-excluded binding.`n. (Join-Path `$PSScriptRoot '..\..\..\..\tools\lib\mir4\ExperimentalApiSdk.ps1')`nExport-ModuleMember -Function New-MIR4ApiRecord,Test-MIR4ApiRecord,ConvertTo-MIR4ApiCanonicalJson,Get-MIR4ApiDigest`n"
 $out['sdk/experimental/mir4/lua/mir4_api_v0.lua']=@'
-- Generated experimental package-excluded binding.
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
 $rows=@($a.contracts|%{"| ``$($_.kind)`` | $($_.description) |"});$out['docs/reference/generated/mir4-experimental-api-v0.md']="---`ntitle: `"MIR 4 Experimental API V0`"`nstatus: current`napplies_to: `"4.0 bootstrap tooling`"`naudience: developer`ndoc_type: reference`nowner: mir-maintainers`nlast_reviewed: 2026-08-17`nsupersedes: []`nsuperseded_by: []`n---`n# MIR 4 Experimental API V0`n`nGenerated from ``spec/api/mir4-v0/contracts.json``. This is package-excluded, read-only experimental tooling, not stable MEP 1.0 or a public support contract.`n`n| Kind | Purpose |`n| --- | --- |`n$($rows-join"`n")`n`nCanonical JSON recursively sorts object keys, preserves array order, uses compact UTF-8, and hashes the record with ``digest`` omitted. Unknown top-level fields, invalid reverse-DNS namespaces, more than 128 capabilities, more than 32 extensions, and digest mismatch fail closed.`n`nTarget transports: f210 may use a proven read-only projection; f200 remains stage-local/package-excluded; f110 and f100 use build-time static manifests. Mutable compiler context, executors, and safety internals are never exposed.`n"
 foreach($e in $out.GetEnumerator()){$p=Join-Path $RepoRoot $e.Key;$b=[Text.UTF8Encoding]::new($false).GetBytes(([string]$e.Value).Replace("`r`n","`n"));if($Check){if(-not(Test-Path $p)-or-not[Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($p),[byte[]]$b)){throw "[mir4-sdk-stale] $($e.Key)"}}else{New-Item -ItemType Directory -Force(Split-Path $p -Parent)|Out-Null;[IO.File]::WriteAllBytes($p,$b)}}
}
