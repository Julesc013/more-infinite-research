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
 $rows=@($a.contracts|%{"| ``$($_.kind)`` | $($_.description) |"});$out['docs/reference/generated/mir4-experimental-api-v0.md']="---`ntitle: `"MIR 4 API/SDK V0 Preview`"`nstatus: deprecated`napplies_to: `"4.0 developer preview migration input`"`naudience: developer`ndoc_type: reference`nowner: mir-maintainers`nlast_reviewed: 2026-08-24`nsupersedes: []`nsuperseded_by:`n  - docs/reference/generated/mir4-api-sdk-v1.md`n---`n# MIR 4 API/SDK V0 Preview`n`n> Deprecated compatibility input. Use API/SDK V1 for new consumers; retain V0 only for deterministic V0-to-V1 migration.`n`nGenerated from ``spec/api/mir4-v0/contracts.json``. This package-excluded, read-only tooling does not establish a player support claim.`n`n## Migration checks`n`n- ``.\tools\mir.ps1 mir4 sdk generate```n- ``.\tools\mir.ps1 mir4 sdk check```n- ``.\tools\mir.ps1 mir4 api check```n- ``.\tools\mir.ps1 mir4 api conformance```n`n| Kind | Purpose |`n| --- | --- |`n$($rows-join"`n")`n`nCanonical JSON recursively sorts object keys, preserves array order, uses compact UTF-8, and hashes the record with ``digest`` omitted. Unknown top-level fields, invalid reverse-DNS namespaces, more than 128 capabilities, more than 32 extensions, and digest mismatch fail closed.`n`nTarget transports are read-only. Mutable compiler context, executors, SafetyKernel internals, and prototype emission are never exposed. V0 source artifacts remain package-excluded migration inputs and are not emitted as release-facing preview archives.`n"
 $out['docs/reference/generated/mir4-experimental-api-v0.md']=$out['docs/reference/generated/mir4-experimental-api-v0.md'].Replace("superseded_by:`n  - docs/reference/generated/mir4-api-sdk-v1.md`n---","superseded_by:`n  - docs/reference/generated/mir4-api-sdk-v1.md`nsource_of_truth_for:`n  - generated-api-v0-migration-reference`n---")
 foreach($e in $out.GetEnumerator()){$p=Join-Path $RepoRoot $e.Key;$b=[Text.UTF8Encoding]::new($false).GetBytes(([string]$e.Value).Replace("`r`n","`n"));if($Check){if(-not(Test-Path $p)-or-not[Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($p),[byte[]]$b)){throw "[mir4-sdk-stale] $($e.Key)"}}else{New-Item -ItemType Directory -Force(Split-Path $p -Parent)|Out-Null;[IO.File]::WriteAllBytes($p,$b)}}
}

function Get-MIR4ModuleEcosystemSdkFiles {
  param([Parameter(Mandatory)][string]$RepoRoot)
  . (Join-Path $RepoRoot 'tools/lib/mir4/ModuleEcosystem.ps1')
  . (Join-Path $RepoRoot 'tools/lib/mir4/ExtensionDeveloperExperience.ps1')
  . (Join-Path $RepoRoot 'tools/lib/mir4/MepDiscovery.ps1')
  . (Join-Path $RepoRoot 'tools/lib/mir4/SdkV1.ps1')
  $authority = Get-MIR4ModuleEcosystemAuthority -RepoRoot $RepoRoot
  $mepSchema = Get-MIR4MepV1Schema -Authority $authority
  $apiSchema = Get-MIR4ApiV1Schema -Authority $authority
  $reference = New-MIR4ReferenceExtensionV1 -RepoRoot $RepoRoot
  $closure = Resolve-MIR4ExtensionClosureV1 -RepoRoot $RepoRoot -Extensions @($reference) -Target f210
  $transport = New-MIR4TargetTransportPlanV1 -RepoRoot $RepoRoot
  $apiAvailable = New-MIR4ApiV1Response -RepoRoot $RepoRoot -Surface query -Target f210 -Items @([ordered]@{id='alpha';status='known'},[ordered]@{id='beta';status='known'}) -Limit 1 -Evidence @('vector:available')
  $apiUnavailable = New-MIR4ApiV1Response -RepoRoot $RepoRoot -Surface observation -Target f012 -Availability unavailable -Reason 'The museum target has no admitted observation transport.' -Evidence @('target:f012','admission:BLOCKED_WITH_EVIDENCE')
  $sdkV1Corpus = New-MIR4SdkV1ConformanceCorpus -RepoRoot $RepoRoot
  $forbidden = (($reference | ConvertTo-Json -Depth 100) | ConvertFrom-Json)
  $forbidden.fragments[0].data | Add-Member -NotePropertyName callback -NotePropertyValue 'forbidden'
  $missing = (($reference | ConvertTo-Json -Depth 100) | ConvertFrom-Json)
  $missing.extension_id='org.example.missing';$missing.namespace='org.example.missing';$missing.fragments[5].data.extension_id='org.example.not-installed';$missing.digest='';$missing.digest=Get-MIR4ModuleDigest $missing
  $cycleA = (($reference | ConvertTo-Json -Depth 100) | ConvertFrom-Json);$cycleA.extension_id='org.example.cycle-a';$cycleA.namespace='org.example.cycle-a';$cycleA.fragments[5].data.extension_id='org.example.cycle-b';$cycleA.digest='';$cycleA.digest=Get-MIR4ModuleDigest $cycleA
  $cycleB = (($reference | ConvertTo-Json -Depth 100) | ConvertFrom-Json);$cycleB.extension_id='org.example.cycle-b';$cycleB.namespace='org.example.cycle-b';$cycleB.fragments[5].data.extension_id='org.example.cycle-a';$cycleB.digest='';$cycleB.digest=Get-MIR4ModuleDigest $cycleB
  $minimal = New-MIR4ExtensionTemplateV1 -RepoRoot $RepoRoot -ExtensionId 'org.example.minimal' -Template minimal
  $unavailable = New-MIR4ExtensionTemplateV1 -RepoRoot $RepoRoot -ExtensionId 'org.example.unavailable' -Template unavailable
  $conflictA = New-MIR4ExtensionTemplateV1 -RepoRoot $RepoRoot -ExtensionId 'org.example.conflict-a' -Template minimal
  $conflictA.fragments += [pscustomobject][ordered]@{id='org.example.conflict-a.conflict';kind='ExtensionConflict';data=[ordered]@{extension_ids=@('org.example.conflict-b')}}
  $conflictA.digest='';$conflictA.digest=Get-MIR4ModuleDigest $conflictA
  $conflictB = New-MIR4ExtensionTemplateV1 -RepoRoot $RepoRoot -ExtensionId 'org.example.conflict-b' -Template minimal
  $conflictB.fragments += [pscustomobject][ordered]@{id='org.example.conflict-b.conflict';kind='ExtensionConflict';data=[ordered]@{extension_ids=@('org.example.conflict-a')}}
  $conflictB.digest='';$conflictB.digest=Get-MIR4ModuleDigest $conflictB
  $discoveryAddon = (($minimal | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100)
  $discoveryAddon.extension_id='org.example.discovery-addon';$discoveryAddon.namespace='org.example.discovery-addon';$discoveryAddon.extension_version='1.0.0-preview'
  foreach($fragment in @($discoveryAddon.fragments)){$fragment.id=$fragment.id.Replace('org.example.minimal','org.example.discovery-addon')}
  @($discoveryAddon.fragments|Where-Object kind -eq 'ExtensionDependency')[0].data.extension_id='org.more-infinite-research.reference'
  $discoveryAddon.digest='';$discoveryAddon.digest=Get-MIR4ModuleDigest $discoveryAddon
  $environmentLock=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'sdk/preview/mir4/reference/environment-lock-f210-v1.json')|ConvertFrom-Json -Depth 100
  $discoveryRecordReference=[pscustomobject][ordered]@{name='mir-reference--mep-v1';data_type='more-infinite-research.extension.v1';data=$reference}
  $discoveryRecordAddon=[pscustomobject][ordered]@{name='example-addon--mep-v1';data_type='more-infinite-research.extension.v1';data=$discoveryAddon}
  $discoveryRecordIgnored=[pscustomobject][ordered]@{name='example-unrelated';data_type='example.unrelated';data=[pscustomobject]@{note='ignored-by-exact-data-type'}}
  $discoverySnapshotA=[pscustomobject][ordered]@{schema=1;kind='MIR4F210ModDataSnapshotV1';target='f210';factorio_line='2.1';environment_lock_digest=[string]$environmentLock.digest;host=[pscustomobject][ordered]@{present=$true;id='org.more-infinite-research.platform';version='0.5.0-preview'};records=@($discoveryRecordReference,$discoveryRecordIgnored,$discoveryRecordAddon)}
  $discoverySnapshotB=[pscustomobject][ordered]@{schema=1;kind='MIR4F210ModDataSnapshotV1';target='f210';factorio_line='2.1';environment_lock_digest=[string]$environmentLock.digest;host=[pscustomobject][ordered]@{present=$true;id='org.more-infinite-research.platform';version='0.5.0-preview'};records=@($discoveryRecordAddon,$discoveryRecordReference,$discoveryRecordIgnored)}
  $discoveryHostAbsent=Copy-MIR4F210MepDiscoveryValueV1 $discoverySnapshotA;$discoveryHostAbsent.host=[pscustomobject][ordered]@{present=$false;id=$null;version=$null}
  $discoveryConflict=[pscustomobject][ordered]@{schema=1;kind='MIR4F210ModDataSnapshotV1';target='f210';factorio_line='2.1';environment_lock_digest=[string]$environmentLock.digest;host=[pscustomobject][ordered]@{present=$true;id='org.more-infinite-research.platform';version='0.5.0-preview'};records=@([pscustomobject][ordered]@{name='conflict-a--mep-v1';data_type='more-infinite-research.extension.v1';data=$conflictA},[pscustomobject][ordered]@{name='conflict-b--mep-v1';data_type='more-infinite-research.extension.v1';data=$conflictB})}
  $discoveryInvalid=[pscustomobject][ordered]@{schema=1;kind='MIR4F210ModDataSnapshotV1';target='f210';factorio_line='2.1';environment_lock_digest=[string]$environmentLock.digest;host=[pscustomobject][ordered]@{present=$true;id='org.more-infinite-research.platform';version='0.5.0-preview'};records=@([pscustomobject][ordered]@{name='invalid--mep-v1';data_type='more-infinite-research.extension.v1';data=$forbidden})}
  $discoveryResult=New-MIR4F210MepDiscoveryV1 -RepoRoot $RepoRoot -Snapshot $discoverySnapshotA
  $migrationV0 = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'sdk/preview/mir4/reference-extension/extension.json')|ConvertFrom-Json -Depth 100
  $migrationV1 = ConvertFrom-MIR4MepV0ToV1 -Envelope $migrationV0
  $files = [ordered]@{}
  $files['sdk/preview/mir4/canonical-json-v1/powershell/MIR4.CanonicalJson.V1.psm1'] = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/lib/mir4/CanonicalJsonV1.ps1')
  $files['sdk/preview/mir4/canonical-json-v1/python/mir4_canonical_json_v1.py'] = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'spec/canonicalization/reference/mir4_canonical_json_v1.py')
  $files['sdk/preview/mir4/api-v1/diagnostics.json'] = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'spec/api/mir4-v1/diagnostics.json')
  $files['sdk/preview/mir4/api-v1/compatibility.json'] = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'spec/api/mir4-v1/compatibility.json')
  $files['sdk/preview/mir4/api-v1/schema-namespace.json'] = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'spec/api/mir4-v1/schema-namespace.json')
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
local function sorted_keys(value)
  local out = {}; for key, _ in pairs(value or {}) do out[#out + 1] = key end
  table.sort(out); return out
end
function M.discover_mod_data(mod_data, host_present)
  local result = {status=host_present and 'discovered' or 'host-absent-inert',records={},diagnostics={},mutation_authorized=false,prototype_write_authorized=false}
  if not host_present then return result end
  local by_id, namespaces, edges = {}, {}, {}
  for _, name in ipairs(sorted_keys(mod_data)) do
    local prototype = mod_data[name]
    if type(prototype) == 'table' and prototype.data_type == 'more-infinite-research.extension.v1' then
      local envelope = prototype.data
      local ok, err = M.validate(envelope)
      if not ok then result.status='quarantined';result.diagnostics[#result.diagnostics+1]=err
      elseif by_id[envelope.extension_id] or namespaces[envelope.namespace] then result.status='quarantined';result.diagnostics[#result.diagnostics+1]='mir4-mep-v1-duplicate-extension'
      else
        by_id[envelope.extension_id]=envelope;namespaces[envelope.namespace]=envelope.extension_id;edges[envelope.extension_id]={}
        result.records[#result.records+1]={prototype_name=name,extension_id=envelope.extension_id,status='validated'}
      end
    end
  end
  if result.status == 'quarantined' then return result end
  for id, envelope in pairs(by_id) do
    for _, fragment in ipairs(envelope.fragments) do
      if fragment.kind == 'ExtensionDependency' and fragment.data.extension_id ~= 'org.more-infinite-research.platform' then
        local dependency=fragment.data.extension_id
        if not by_id[dependency] then result.status='quarantined';result.diagnostics[#result.diagnostics+1]='mir4-mep-v1-missing-dependency';return result end
        edges[id][#edges[id]+1]=dependency
      elseif fragment.kind == 'ExtensionConflict' then
        for _, conflict in ipairs(fragment.data.extension_ids or {}) do
          if by_id[conflict] then result.status='quarantined';result.diagnostics[#result.diagnostics+1]='mir4-mep-v1-conflict';return result end
        end
      end
    end
  end
  local remaining, order = {}, {}
  for id, dependencies in pairs(edges) do remaining[id]=dependencies end
  while next(remaining) do
    local ready={};for id, dependencies in pairs(remaining) do if #dependencies==0 then ready[#ready+1]=id end end;table.sort(ready)
    if #ready==0 then result.status='quarantined';result.diagnostics[#result.diagnostics+1]='mir4-mep-v1-dependency-cycle';return result end
    for _, id in ipairs(ready) do
      order[#order+1]=id;remaining[id]=nil
      for _, dependencies in pairs(remaining) do for index=#dependencies,1,-1 do if dependencies[index]==id then table.remove(dependencies,index) end end end
    end
  end
  result.order=order;return result
end
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
---@field canonicalization 'mir-canonical-json/1'
---@field digest string
'@
  $files['sdk/preview/mir4/api-v1/typescript/index.ts'] = @'
export type Availability = {status: "available" | "unavailable"; reason: string; evidence: string[]};
export type ApiSurface = "host-manifest"|"query"|"profile"|"observation"|"tooling"|"target-provider-abi"|"proof"|"release"|"continuity-bundle";
export interface Mir4ApiResponse<T=unknown>{kind:"MIR4ApiResponseV1";schema:1;surface:ApiSurface;target:{id:string;factorio_line:string;transport:string};versions:{source:string;distribution:string};capabilities:string[];availability:Availability;page:{offset:number;limit:number;returned:number;total:number|null;next_cursor:string|null};items:T[];canonicalization:"mir-canonical-json/1";extensions:Record<string,unknown>;source_identity:unknown;package_visible:false;mutation_authorized:false;public_support_claim:false;digest:string}
export function unavailable(response:Mir4ApiResponse):boolean{return response.availability.status === "unavailable"}
'@
  $files['sdk/preview/mir4/api-v1/python/mir4_api_v1.py'] = @'
"""Generated package-excluded MIR 4 API V1 preview types."""
from dataclasses import dataclass
from typing import Any, Generic, Optional, TypeVar
T = TypeVar("T")
CANONICALIZATION = "mir-canonical-json/1"
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
  foreach($binding in @(
    @{path='sdk/preview/mir4/api-v1/typescript/index.mjs';template='tools/templates/mir4/sdk-v1/typescript/index.mjs'},
    @{path='sdk/preview/mir4/api-v1/typescript/index.ts';template='tools/templates/mir4/sdk-v1/typescript/index.ts'},
    @{path='sdk/preview/mir4/api-v1/typescript/package.json';template='tools/templates/mir4/sdk-v1/typescript/package.json'},
    @{path='sdk/preview/mir4/api-v1/python/mir4_api_v1.py';template='tools/templates/mir4/sdk-v1/python/mir4_api_v1.py'},
    @{path='sdk/preview/mir4/api-v1/powershell/MIR4.Api.V1.psm1';template='tools/templates/mir4/sdk-v1/powershell/MIR4.Api.V1.psm1'},
    @{path='sdk/preview/mir4/api-v1/lua/mir4_api_v1.lua';template='tools/templates/mir4/sdk-v1/lua/mir4_api_v1.lua'},
    @{path='sdk/preview/mir4/api-v1/lua/mir4_api_v1.luals.lua';template='tools/templates/mir4/sdk-v1/lua/mir4_api_v1.luals.lua'},
    @{path='sdk/preview/mir4/conformance-v1/Invoke-MIR4SdkV1Conformance.ps1';template='tools/templates/mir4/sdk-v1/conformance/Invoke-MIR4SdkV1Conformance.ps1'}
  )){$files[$binding.path]=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $binding.template)}
  $files['sdk/preview/mir4/api-v1/conformance/corpus.json']=(ConvertTo-MIR4ModuleCanonicalJson $sdkV1Corpus)+"`n"
  $files['sdk/preview/mir4/api-v1/package-metadata.json']=(ConvertTo-MIR4ModuleCanonicalJson ([ordered]@{
    schema=1;kind='MIR4ApiSdkV1PackageMetadata';name='mir4-api-sdk-v1-preview';version='4.0.0-preview'
    maturity='developer-preview';license='MPL-2.0';canonicalization='mir-canonical-json/1'
    bindings=@('lua','powershell','python','typescript')
    operations=@('parse','validate','canonicalize','digest','capability-negotiation','availability-decoding','bounded-pagination','snapshot-comparison','diagnostic-rendering','extension-validation','manifest-verification','archive-verification')
    conformance=[ordered]@{positive=12;negative=18;accept_reject_identity=$true;canonical_byte_identity=$true;digest_identity=$true}
    package_visible=$false;publication_authorized=$false
  }))+"`n"
  $files['sdk/preview/mir4/api-v1/examples/read-response.ps1']=@'
param([Parameter(Mandatory)][string]$Path)
Import-Module (Join-Path $PSScriptRoot '../powershell/MIR4.Api.V1.psm1') -Force
$response=ConvertFrom-MIR4ApiV1Json -Json (Get-Content -Raw -LiteralPath $Path)
Test-MIR4ApiV1Response $response|Out-Null
$availability=Get-MIR4ApiV1Availability $response
[pscustomobject]@{target=$response.target.id;surface=$response.surface;available=$availability.available;items=@($response.items).Count;digest=$response.digest}
'@
  $files['sdk/preview/mir4/api-v1/examples/read_response.py']=@'
import argparse
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))
import mir4_api_v1 as mir4
parser=argparse.ArgumentParser();parser.add_argument("path",type=Path);args=parser.parse_args()
response=mir4.validate(mir4.parse(args.path.read_text(encoding="utf-8")))
print({"target":response["target"]["id"],"surface":response["surface"],"available":mir4.decode_availability(response)["available"],"items":len(response["items"]),"digest":response["digest"]})
'@
  $files['sdk/preview/mir4/api-v1/examples/README.md']="# MIR 4 API V1 examples`n`nThe PowerShell and Python readers parse, validate, decode availability, and report the immutable response digest. Run them against files in ../vectors. Neither example mutates the player package or grants release authority.`n"
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
  return {kind='MIR4ExtensionEnvelopeV1',schema=1,extension_id=v0.extension_id,extension_version='0.0.0-migrated',namespace=v0.extension_id,targets=v0.targets,fragments=v0.fragments,canonicalization='mir-canonical-json/1',digest='RECOMPUTE-WITH-MIR-CANONICAL-JSON-1'}
end
'@
  $files['sdk/preview/mir4/reference-extension-v1/extension.json']=(ConvertTo-MIR4ModuleCanonicalJson $reference)+"`n"
  $files['sdk/preview/mir4/reference-extension-v1/README.md']="# MIR 4 synthetic external reference extension V1`n`nThis package-excluded extension exercises all 12 data-only fragment kinds. It is a conformance fallback, not an independent production consumer or public compatibility claim.`n"
  $files['sdk/preview/mir4/reference/extension-closure-v1.json']=(ConvertTo-MIR4ModuleCanonicalJson $closure)+"`n"
  $files['sdk/preview/mir4/reference/extension-transport-plan-v1.json']=(ConvertTo-MIR4ModuleCanonicalJson $transport)+"`n"
  $files['sdk/preview/mir4/reference/f210-mep-discovery-v1.json']=(ConvertTo-MIR4ModuleCanonicalJson $discoveryResult)+"`n"
  $files['sdk/preview/mir4/api-v1/vectors/available-page-1.json']=(ConvertTo-MIR4ModuleCanonicalJson $apiAvailable)+"`n"
  $files['sdk/preview/mir4/api-v1/vectors/unavailable-observation-f012.json']=(ConvertTo-MIR4ModuleCanonicalJson $apiUnavailable)+"`n"
  $files['fixtures/mir4-mep-v1/positive/reference-extension.json']=(ConvertTo-MIR4ModuleCanonicalJson $reference)+"`n"
  $files['fixtures/mir4-mep-v1/negative/forbidden-callback.json']=(ConvertTo-MIR4ModuleCanonicalJson $forbidden)+"`n"
  $files['fixtures/mir4-mep-v1/negative/missing-dependency.json']=(ConvertTo-MIR4ModuleCanonicalJson $missing)+"`n"
  $files['fixtures/mir4-mep-v1/negative/cycle-a.json']=(ConvertTo-MIR4ModuleCanonicalJson $cycleA)+"`n"
  $files['fixtures/mir4-mep-v1/negative/cycle-b.json']=(ConvertTo-MIR4ModuleCanonicalJson $cycleB)+"`n"
  $files['fixtures/mir4-mep-discovery-v1/positive/order-a.json']=(ConvertTo-MIR4ModuleCanonicalJson $discoverySnapshotA)+"`n"
  $files['fixtures/mir4-mep-discovery-v1/positive/order-b.json']=(ConvertTo-MIR4ModuleCanonicalJson $discoverySnapshotB)+"`n"
  $files['fixtures/mir4-mep-discovery-v1/positive/host-absent.json']=(ConvertTo-MIR4ModuleCanonicalJson $discoveryHostAbsent)+"`n"
  $files['fixtures/mir4-mep-discovery-v1/negative/conflict.json']=(ConvertTo-MIR4ModuleCanonicalJson $discoveryConflict)+"`n"
  $files['fixtures/mir4-mep-discovery-v1/negative/invalid-envelope.json']=(ConvertTo-MIR4ModuleCanonicalJson $discoveryInvalid)+"`n"
  $files['sdk/preview/mir4/mep-v1/README.md'] = "# MIR Extension Protocol V1 preview`n`nData-only envelopes contribute 12 typed fragment kinds. They cannot carry callbacks, prototype writes, raw compiler context, executors, or SafetyKernel overrides. Resolve dependencies before inspection and treat capability gaps as review-required.`n"
  foreach($generatedExtension in @(
    @{path='sdk/preview/mir4/mep-v1/templates/minimal/extension.json';value=$minimal},
    @{path='sdk/preview/mir4/mep-v1/templates/all-fragments/extension.json';value=$reference},
    @{path='sdk/preview/mir4/mep-v1/templates/unavailable/extension.json';value=$unavailable},
    @{path='sdk/preview/mir4/mep-v1/examples/positive/extension.json';value=$minimal},
    @{path='sdk/preview/mir4/mep-v1/examples/conflict/extension-a.json';value=$conflictA},
    @{path='sdk/preview/mir4/mep-v1/examples/conflict/extension-b.json';value=$conflictB},
    @{path='sdk/preview/mir4/mep-v1/examples/unavailable/extension.json';value=$unavailable},
    @{path='sdk/preview/mir4/mep-v1/examples/migration/extension-v0.json';value=$migrationV0},
    @{path='sdk/preview/mir4/mep-v1/examples/migration/extension-v1.json';value=$migrationV1}
  )) {
    $files[$generatedExtension.path]=(ConvertTo-MIR4ModuleCanonicalJson $generatedExtension.value)+[char]10
  }
  $files['sdk/preview/mir4/mep-v1/package-metadata.json']=(ConvertTo-MIR4ModuleCanonicalJson ([ordered]@{
    schema=1;kind='MIR4MepV1PackageMetadata';name='mir4-mep-v1-preview';version='4.0.0-preview'
    maturity='developer-preview';license='MPL-2.0';canonicalization='mir-canonical-json/1'
    commands=@('ci-init','diff','discover','doctor','explain','init','lock','migrate','package','test','validate')
    templates=@('all-fragments','minimal','unavailable')
    examples=@('conflict','migration','positive','unavailable')
    package_visible=$false;player_mutation_authorized=$false;prototype_write_authorized=$false
    release_authority=$false;publication_authorized=$false
  }))+[char]10
  $files['sdk/preview/mir4/mep-v1/README.md'] = @'
# MIR Extension Protocol V1 preview

This self-contained, offline developer preview supplies minimal, all-fragment, and unavailable templates; positive, conflict, unavailable, migration, and F210 discovery examples; and eleven commands: init, doctor, validate, lock, diff, discover, explain, test, package, migrate, and ci-init.

Start with docs/reference/mir4-first-extension.md. The F210 collector now discovers extension-owned mod-data snapshots, validates envelopes, resolves dependency/conflict closure, and explains shadow plans. It remains package-excluded and read-only; F210 emission/admission is still blocked behind the unchanged terminal emitter.
'@
  $files['docs/reference/generated/mir4-api-sdk-v1.md'] = @'
---
title: "MIR 4 API and SDK V1 Preview"
status: current
applies_to: "4.0 developer preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - generated-mir4-api-sdk-v1-reference
---
# MIR 4 API and SDK V1 Preview

Generated from `spec/api/mir4-v1/contracts.json` and the W05 module-ecosystem authority. The nine APIs return copied, bounded, paginated, capability-labelled data. Unavailability is an explicit status with a reason and evidence; it is never reported as a numeric zero.

V1 records use the permanent `https://julesc013.github.io/more-infinite-research/schemas/mir4/v1/` namespace and `mir-canonical-json/1`: NFC UTF-8 without a BOM, ordinal object keys, preserved generic array order, signed safe integers only, canonical target and timestamp forms, and domain-separated SHA-256 digests. V0 is accepted only by explicit migration readers and is never emitted as V1.

Bindings are provided for JSON Schema, Lua with LuaLS annotations, TypeScript/Node, Python, and PowerShell. Every language binding exposes parse, validate, canonicalize, digest, capability negotiation, availability decoding, bounded pagination, snapshot comparison, diagnostic rendering, extension validation, and manifest/archive verification. Lua uses explicit host ports for canonical JSON, SHA-256, and archive entry I/O because the Factorio sandbox has no general filesystem or ZIP authority.

The generated conformance corpus contains 12 positive and 18 negative cases. PowerShell, Python, and Node must produce identical canonical bytes, digests, and accept/reject sets. The same conformance runner operates from a clean extracted archive. The reference extension and fixtures exercise all 12 fragment kinds. Use `tools/mir.ps1 mir4 extension` for init, validate, explain, test, package, and migrate commands.

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
  $files['sdk/preview/mir4/mep-v1/conformance.ps1'] = @'
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/ExtensionDeveloperExperience.ps1')
$value=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'sdk/preview/mir4/mep-v1/examples/positive/extension.json')|ConvertFrom-Json -Depth 100
Test-MIR4MepV1Envelope -Envelope $value -RepoRoot $RepoRoot|Out-Null
$closure=Resolve-MIR4ExtensionClosureV1 -RepoRoot $RepoRoot -Extensions @($value) -Target f210
$doctor=Get-MIR4ExtensionDoctorV1 -RepoRoot $RepoRoot -Envelope $value
$lock=New-MIR4ExtensionLockV1 -RepoRoot $RepoRoot -Envelope $value -Target f210
$diff=New-MIR4ExtensionDiffV1 -RepoRoot $RepoRoot -Base $value -Candidate $value
$plan=New-MIR4ExtensionShadowPlanV1 -RepoRoot $RepoRoot -Envelope $value -Target f210
if([string]$doctor.status-cne'passed'-or-not[bool]$closure.complete-or[string]$diff.status-cne'identical'-or[string]$plan.result-cne'shadow-complete'){throw '[mir4-mep-v1-conformance]'}
[pscustomobject]@{
  status='passed';maturity='developer-preview';commands=11;offline=$true
  lock_status=[string]$lock.status;player_mutation_authorized=$false;prototype_write_authorized=$false
  production_consumer='BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER'
}|ConvertTo-Json
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
