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