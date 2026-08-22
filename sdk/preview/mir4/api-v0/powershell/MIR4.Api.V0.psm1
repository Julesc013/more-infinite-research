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