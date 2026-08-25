param([Parameter(Mandatory)][string]$Path)
Import-Module (Join-Path $PSScriptRoot '../powershell/MIR4.Api.V1.psm1') -Force
$response=ConvertFrom-MIR4ApiV1Json -Json (Get-Content -Raw -LiteralPath $Path)
Test-MIR4ApiV1Response $response|Out-Null
$availability=Get-MIR4ApiV1Availability $response
[pscustomobject]@{target=$response.target.id;surface=$response.surface;available=$availability.available;items=@($response.items).Count;digest=$response.digest}