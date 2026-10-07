# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$OutputRoot='build/tests/inspector-export-consumers'
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/inspection/Inspector.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
if(-not$root.StartsWith((Join-Path $repo 'build')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw '[mir4-inspector-consumer-output-root]'}
$run=Join-Path $root ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $run|Out-Null
$encoding=[Text.UTF8Encoding]::new($false)
$exporter=Get-MIR4InspectorV1ExporterPowerShell
[void][ScriptBlock]::Create($exporter)
[IO.File]::WriteAllText((Join-Path $run 'Export.ps1'),$exporter,$encoding)
[IO.File]::WriteAllText((Join-Path $run 'index.html'),(Get-MIR4InspectorV1Html),$encoding)
$referencePath=Join-Path $repo 'sdk/preview/mir4/reference/inspection-bundle-v1.json'
$reference=Get-Content -Raw -LiteralPath $referencePath|ConvertFrom-Json -AsHashtable -Depth 100
$vectors=[Collections.Generic.List[object]]::new()
function Add-InspectorVector([string]$Name,[scriptblock]$Change,[string]$Expected=''){
  $value=ConvertTo-Json -InputObject $reference -Depth 100 -Compress|ConvertFrom-Json -AsHashtable -Depth 100
  & $Change $value
  $vectors.Add([ordered]@{name=$Name;value=$value;accepted=($Expected-eq'');error=$Expected})
}
Add-InspectorVector canonical {}
Add-InspectorVector ascii-limit {param($v)$v.sections[0].items[0].message='a'*4096}
Add-InspectorVector utf8-limit {param($v)$v.sections[0].items[0].message=([string][char]0xE9)*2048}
Add-InspectorVector astral-limit {param($v)$v.sections[0].items[0].message=[char]::ConvertFromUtf32(0x1F680)*1024}
Add-InspectorVector ascii-over {param($v)$v.sections[0].items[0].message='a'*4097} string
Add-InspectorVector utf8-over {param($v)$v.sections[0].items[0].message=([string][char]0xE9)*2049} string
Add-InspectorVector array-string-over {param($v)$v.sections[0].items[0].messages=@('a'*4097)} string
Add-InspectorVector excessive-depth {param($v)$nested='leaf';for($i=0;$i-lt6;$i++){$nested=@{child=$nested}};$v.sections[0].items[0].extra=$nested} depth
Add-InspectorVector excessive-properties {param($v)$obj=@{};for($i=0;$i-lt101;$i++){$obj['key'+$i]=$i};$v.sections[0].items[0].extra=$obj} properties
Add-InspectorVector duplicate-section {param($v)$v.sections[1].id=$v.sections[0].id} section
Add-InspectorVector object-items {param($v)$v.sections[0].items=@{message='not-an-array'}} section
Add-InspectorVector wrong-returned {param($v)$v.sections[0].returned=0} section
Add-InspectorVector wrong-label {param($v)$v.sections[0].label='Other'} section
Add-InspectorVector section-extra {param($v)$v.sections[0].other='field'} section
Add-InspectorVector source-missing {param($v)$v.Remove('source_identity')} bundle
Add-InspectorVector source-type {param($v)$v.source_identity='not-an-object'} bundle
Add-InspectorVector digest-shape {param($v)$v.digest='not-a-digest'} bundle
Add-InspectorVector input-digest-shape {param($v)$v.input_digests.compilation.sha256='not-a-digest'} bundle
Add-InspectorVector false-read-only {param($v)$v.local_file_api_only=$false} header
Add-InspectorVector forged-release {param($v)$v.public_release_proof=$true} header
Add-InspectorVector string-schema {param($v)$v.schema='1'} header
Add-InspectorVector widened-bounds {param($v)$v.bounds.max_string_bytes=99999} bounds
Add-InspectorVector unsupported-pack-claim {param($v)$v.sections[0].items[0]['Modpack-Supported']=$true} forbidden
$contract=Get-MIR4InspectorV1ConsumerContract
foreach($field in $contract.forbidden){
  $value=ConvertTo-Json -InputObject $reference -Depth 100 -Compress|ConvertFrom-Json -AsHashtable -Depth 100
  $value.sections[0].items[0][$field]='controlled-forbidden-value'
  $vectors.Add([ordered]@{name=('forbidden-'+$field);value=$value;accepted=$false;error='forbidden'})
}
$observations=[Collections.Generic.List[object]]::new()
$sentinel='existing output must survive a rejected input'
for($index=0;$index-lt$vectors.Count;$index++){
  $vector=$vectors[$index]
  $inputPath=Join-Path $run ($index.ToString('D2')+'-input.json')
  $outputPath=Join-Path $run ($index.ToString('D2')+'-output.json')
  [IO.File]::WriteAllText($inputPath,(ConvertTo-Json -InputObject $vector.value -Depth 100),$encoding)
  [IO.File]::WriteAllText($outputPath,$sentinel,$encoding)
  $log=@(& pwsh -NoProfile -File (Join-Path $run 'Export.ps1') -InputPath $inputPath -OutputPath $outputPath 2>&1|ForEach-Object ToString)-join"`n"
  $exit=$LASTEXITCODE
  if($vector.accepted){
    if($exit-ne0){throw "[mir4-inspector-consumer-positive] $($vector.name): $log"}
    $roundtrip=Get-Content -Raw -LiteralPath $outputPath|ConvertFrom-Json -AsHashtable -Depth 100
    if((ConvertTo-Json -InputObject $roundtrip -Depth 100 -Compress)-cne(ConvertTo-Json -InputObject $vector.value -Depth 100 -Compress)){throw "[mir4-inspector-consumer-roundtrip] $($vector.name)"}
  }else{
    if($exit-eq0-or$log-notmatch[regex]::Escape('[mir4-inspector-v1-'+$vector.error+']')){throw "[mir4-inspector-consumer-negative] $($vector.name): $log"}
    if([IO.File]::ReadAllText($outputPath)-cne$sentinel){throw "[mir4-inspector-consumer-negative-output] $($vector.name)"}
  }
  $observations.Add([ordered]@{name=$vector.name;accepted=$vector.accepted;expected_error=$vector.error;exit=$exit})
}
# A length-only fixture verifies refusal before parsing; no multi-megabyte
# mod or string payload is copied. Retire only this proven disposable input.
$largePath=Join-Path $run 'over-byte-limit.json'
$large=[IO.File]::Open($largePath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$large.SetLength([long]$contract.limits.bytes+1)}finally{$large.Dispose()}
$largeOutput=Join-Path $run 'over-byte-limit-output.json'
[IO.File]::WriteAllText($largeOutput,$sentinel,$encoding)
$largeLog=@(& pwsh -NoProfile -File (Join-Path $run 'Export.ps1') -InputPath $largePath -OutputPath $largeOutput 2>&1|ForEach-Object ToString)-join"`n"
if($LASTEXITCODE-eq0-or$largeLog-notmatch'\[mir4-inspector-v1-bytes\]'-or[IO.File]::ReadAllText($largeOutput)-cne$sentinel){throw '[mir4-inspector-consumer-input-bytes]'}
if(-not[IO.Path]::GetFullPath($largePath).StartsWith($run+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw '[mir4-inspector-consumer-disposable-path]'}
Remove-Item -LiteralPath $largePath
$browserPath=Join-Path $run 'vectors.json'
[IO.File]::WriteAllText($browserPath,(ConvertTo-Json -InputObject ([ordered]@{vectors=@($vectors)}) -Depth 100),$encoding)
$browserStatus='not-run; Node unavailable; vectors retained for another V8 host'
if(Get-Command node -ErrorAction SilentlyContinue){
  & node (Join-Path $repo 'tests/inspection/inspector_export_consumers.js') $run
  if($LASTEXITCODE-ne0){throw '[mir4-inspector-consumer-browser-vectors]'}
  $browserStatus='passed-actual-generated-validator-in-Node; no-DOM-or-browser-interaction-proof'
}
$global:LASTEXITCODE=0
$result=[ordered]@{status='passed-actual-generated-powershell-export-consumer';cases=$observations.Count;input_byte_refusal=$true;negative_output_preserved=$true;source_sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'tools/mir/application/inspection/Inspector.ps1')).Hash;reference_sha256=(Get-FileHash -LiteralPath $referencePath).Hash;browser_validation=$browserStatus;browser_vectors=$browserPath;run=$run;factorio_processes=0;dependency_payload_bytes_copied=0;public_release_proof=$false}
[IO.File]::WriteAllText((Join-Path $run 'result.json'),(ConvertTo-Json -InputObject $result -Depth 20),$encoding)
$result|ConvertTo-Json -Depth 20
