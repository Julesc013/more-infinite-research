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