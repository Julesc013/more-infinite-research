param(
  [Parameter(Mandatory)]
  [ValidateSet('api-check', 'api-conformance', 'sdk-generate', 'sdk-check')]
  [string]$Command,
  [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}
. (Join-Path $RepoRoot 'tools\lib\mir4\ExperimentalApiSdk.ps1')

if ($Command -eq 'sdk-generate') {
  Invoke-MIR4SdkGenerate -RepoRoot $RepoRoot
  Write-Host 'MIR4 developer-preview SDK generated.'
  exit
}
Invoke-MIR4SdkGenerate -RepoRoot $RepoRoot -Check
$positive = Get-ChildItem (Join-Path $RepoRoot 'fixtures\mir4-api-v0\positive') -Filter *.json
$reference = Get-ChildItem (Join-Path $RepoRoot 'fixtures\mir4-api-v0\reference') -Filter *.json
foreach ($file in @($positive) + @($reference)) {
  $record = Get-Content -Raw $file.FullName | ConvertFrom-Json
  Test-MIR4ApiRecord $record -RepoRoot $RepoRoot | Out-Null
}
if($Command-eq'api-conformance'){
 foreach($file in Get-ChildItem (Join-Path $RepoRoot 'fixtures\mir4-api-v0\negative') -Filter *.json){$v=Get-Content -Raw $file.FullName|ConvertFrom-Json;$expected=[string]$v.expected_diagnostic;$v.PSObject.Properties.Remove('expected_diagnostic');try{Test-MIR4ApiRecord $v -RepoRoot $RepoRoot|Out-Null;throw '[mir4-api-negative-accepted] Negative fixture was accepted.'}catch{if(-not $_.Exception.Message.StartsWith("[$expected]")){throw "[mir4-api-negative-diagnostic] Expected $expected for $($file.Name), got $($_.Exception.Message)"}}}
 $source=Get-Content -Raw(Join-Path $RepoRoot 'fixtures\mir4-api-v0\reference\extension-profile.json')|ConvertFrom-Json
 $roundTrip=(ConvertTo-MIR4ApiCanonicalJson $source)|ConvertFrom-Json
 if((ConvertTo-MIR4ApiCanonicalJson $source)-cne(ConvertTo-MIR4ApiCanonicalJson $roundTrip)){throw '[mir4-api-round-trip] Reference example changed.'}
 $reverse=[ordered]@{};foreach($property in @($source.PSObject.Properties|Sort-Object Name -Descending)){$reverse[$property.Name]=$property.Value}
 if((ConvertTo-MIR4ApiCanonicalJson $source)-cne(ConvertTo-MIR4ApiCanonicalJson $reverse)){throw '[mir4-api-canonicalization] Object property order changed canonical bytes.'}
 if((ConvertTo-MIR4ApiCanonicalJson ([ordered]@{empty=@()}))-cne'{"empty":[]}'){throw '[mir4-api-canonical-empty-array] Empty arrays must not collapse to null.'}
}
Write-Host "MIR4 developer-preview $Command passed."
