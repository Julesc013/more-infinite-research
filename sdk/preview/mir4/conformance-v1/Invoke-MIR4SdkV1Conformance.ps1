param([string]$SdkRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $SdkRoot 'api-v1/powershell/MIR4.Api.V1.psm1') -Force
$available=Get-Content -Raw -LiteralPath (Join-Path $SdkRoot 'api-v1/vectors/available-page-1.json')|ConvertFrom-Json
$unavailable=Get-Content -Raw -LiteralPath (Join-Path $SdkRoot 'api-v1/vectors/unavailable-observation-f012.json')|ConvertFrom-Json
Test-MIR4ApiV1Availability $available|Out-Null
Test-MIR4ApiV1Availability $unavailable|Out-Null
$copy=Copy-MIR4ApiV1Data $available
$copy.items=@()
if(@($available.items).Count-eq 0){throw '[mir4-sdk-v1-copy-isolation]'}
$extension=Get-Content -Raw -LiteralPath (Join-Path $SdkRoot 'reference-extension-v1/extension.json')|ConvertFrom-Json
$schema=Join-Path $SdkRoot 'mep-v1/json-schema/mir4-mep-v1.schema.json'
if(-not(($extension|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile $schema)){throw '[mir4-sdk-v1-mep-schema]'}
if(@($extension.fragments).Count-ne 12){throw '[mir4-sdk-v1-fragment-count]'}
Write-Host '[ok] standalone MIR 4 SDK V1 conformance passed.'