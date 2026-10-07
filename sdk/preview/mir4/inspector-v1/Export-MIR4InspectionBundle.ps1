param([Parameter(Mandatory)][string]$InputPath,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$contract='{"bounds":{"default_page_items":25,"max_page_items":50,"max_sections":11,"max_items_per_section":100,"max_string_bytes":4096,"max_object_depth":8,"cursor_format":"decimal-offset","copy_mode":"canonical-json-deep-copy"},"limits":{"sections":11,"items":100,"page":25,"depth":8,"string":4096,"properties":100,"bytes":8388608},"forbidden":["callback","callbacks","compiler_context","CompilerContext","data_raw","executor","executors","function","functions","operation","operations","prototype","prototypes","prototype_write","safety_kernel","secret","secrets"],"required":["schema","kind","programme_id","source_identity","maturity","authority","input_digests","bounds","sections","section_count","local_file_api_only","network_or_upload_authorized","raw_mutable_compiler_objects","idle_runtime_work","package_visible","public_release_proof","player_mutation_authorized","digest"],"section_fields":["id","label","item_count","returned","truncated","items"],"digest_pattern":"^sha256:[0-9a-f]{64}$","input_digest_count":8,"labels":["Overview","Capabilities","Research streams","Recipe/productivity coverage","Compatibility","Diagnostics","Settings/profile","Target dispositions","Migration status","Proof status","Export"],"header":{"schema":1,"kind":"MIR4InspectionBundleV1","programme_id":"M4C02-09-24H","maturity":"developer-preview","authority":"W07-copied-bounded-read-only-DTOs","section_count":11,"local_file_api_only":true,"network_or_upload_authorized":false,"raw_mutable_compiler_objects":false,"idle_runtime_work":false,"package_visible":false,"public_release_proof":false,"player_mutation_authorized":false}}'|ConvertFrom-Json -AsHashtable
$encoding=[Text.UTF8Encoding]::new($false,$true)
function Test-InspectionValue([AllowNull()]$Value,[int]$Depth=0){
  if($null-eq$Value){return}
  if($Value-is[string]){if($encoding.GetByteCount($Value)-gt$contract.limits.string){throw '[mir4-inspector-v1-string]'};return}
  if($Value-is[Collections.IDictionary]){
    if($Depth-gt$contract.limits.depth){throw '[mir4-inspector-v1-depth]'}
    if($Value.Count-gt$contract.limits.properties){throw '[mir4-inspector-v1-properties]'}
    foreach($key in $Value.Keys){
      if($key-cin$contract.forbidden-or$key-match'(?i)^modpack[_-]?supported$'){throw '[mir4-inspector-v1-forbidden]'}
      Test-InspectionValue ([string]$key)
      Test-InspectionValue $Value[$key] ($Depth+1)
    }
  }elseif($Value-is[Collections.IList]){
    if($Depth-gt$contract.limits.depth){throw '[mir4-inspector-v1-depth]'}
    if($Value.Count-gt$contract.limits.items){throw '[mir4-inspector-v1-items]'}
    foreach($item in $Value){Test-InspectionValue $item ($Depth+1)}
  }elseif($Value-is[double]-and-not[double]::IsFinite($Value)){throw '[mir4-inspector-v1-number]'}
}
function Test-InspectionInteger($Value){
  return ($Value-is[long]-or$Value-is[int]-or$Value-is[double]-or$Value-is[decimal])-and[double]::IsFinite([double]$Value)-and[Math]::Floor([double]$Value)-eq$Value-and[Math]::Abs([double]$Value)-le9007199254740991
}
function Test-InspectionScalar($Value,$Expected){
  if($Expected-is[bool]){return $Value-is[bool]-and$Value-eq$Expected}
  if($Expected-is[string]){return $Value-is[string]-and$Value-ceq$Expected}
  return (Test-InspectionInteger $Value)-and$Value-eq$Expected
}
# Hold the input against writers while enforcing its byte limit and parsing.
$stream=[IO.File]::Open($InputPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try{
  if($stream.Length-gt$contract.limits.bytes){throw '[mir4-inspector-v1-bytes]'}
  $reader=[IO.StreamReader]::new($stream,$encoding,$true)
  try{$record=ConvertFrom-Json -InputObject $reader.ReadToEnd() -AsHashtable -NoEnumerate -Depth 100}finally{$reader.Dispose()}
}finally{$stream.Dispose()}
Test-InspectionValue $record
if($record-isnot[Collections.IDictionary]-or$record.Count-ne$contract.required.Count){throw '[mir4-inspector-v1-bundle]'}
foreach($key in $contract.required){if(-not$record.Contains($key)){throw '[mir4-inspector-v1-bundle]'}}
foreach($key in $contract.header.Keys){if(-not(Test-InspectionScalar $record[$key] $contract.header[$key])){throw '[mir4-inspector-v1-header]'}}
if($null-ne$record.source_identity-and$record.source_identity-isnot[Collections.IDictionary]){throw '[mir4-inspector-v1-bundle]'}
if($record.digest-isnot[string]-or$record.digest-cnotmatch$contract.digest_pattern-or$record.input_digests-isnot[Collections.IDictionary]-or$record.input_digests.Count-ne$contract.input_digest_count){throw '[mir4-inspector-v1-bundle]'}
foreach($identity in $record.input_digests.Values){if($identity-isnot[Collections.IDictionary]-or$identity.path-isnot[string]-or-not$identity.path-or$identity.sha256-isnot[string]-or$identity.sha256-cnotmatch'^[0-9a-f]{64}$'){throw '[mir4-inspector-v1-bundle]'}}
if($record.bounds-isnot[Collections.IDictionary]-or$record.bounds.Count-ne$contract.bounds.Count){throw '[mir4-inspector-v1-bounds]'}
foreach($key in $contract.bounds.Keys){if(-not(Test-InspectionScalar $record.bounds[$key] $contract.bounds[$key])){throw '[mir4-inspector-v1-bounds]'}}
if($record.sections-isnot[Collections.IList]-or$record.sections.Count-ne$contract.limits.sections){throw '[mir4-inspector-v1-sections]'}
$ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
for($index=0;$index-lt$record.sections.Count;$index++){
  $section=$record.sections[$index]
  if($section-isnot[Collections.IDictionary]-or$section.Count-ne$contract.section_fields.Count-or$section.id-isnot[string]-or$section.id-cnotmatch'^[a-z][a-z0-9-]+$'-or-not$ids.Add($section.id)-or$section.label-cne$contract.labels[$index]-or$section.truncated-isnot[bool]-or-not(Test-InspectionInteger $section.item_count)-or-not(Test-InspectionInteger $section.returned)-or$section.returned-lt0-or$section.item_count-lt$section.returned-or$section.items-isnot[Collections.IList]-or$section.items.Count-ne$section.returned-or$section.returned-gt$contract.limits.items){throw '[mir4-inspector-v1-section]'}
  foreach($key in $contract.section_fields){if(-not$section.Contains($key)){throw '[mir4-inspector-v1-section]'}}
}
$json=ConvertTo-Json -InputObject $record -Depth 100
if($encoding.GetByteCount($json+"`n")-gt$contract.limits.bytes){throw '[mir4-inspector-v1-bytes]'}
[IO.File]::WriteAllText($OutputPath,$json+"`n",$encoding)
[pscustomobject]@{status='exported-bounded-read-only';path=$OutputPath;upload=$false;mutation=$false}|ConvertTo-Json