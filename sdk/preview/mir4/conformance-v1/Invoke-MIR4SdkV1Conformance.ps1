param(
  [string]$SdkRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [switch]$RequireNode
)
$ErrorActionPreference='Stop'
$corpusPath=Join-Path $SdkRoot 'api-v1/conformance/corpus.json'
$corpus=Get-Content -Raw -LiteralPath $corpusPath|ConvertFrom-Json -Depth 100
if(@($corpus.positive).Count-lt12-or@($corpus.negative).Count-lt16){throw '[mir4-sdk-v1-corpus-cardinality]'}
Import-Module (Join-Path $SdkRoot 'api-v1/powershell/MIR4.Api.V1.psm1') -Force
$accepted=[Collections.Generic.List[string]]::new();$rejected=[Collections.Generic.List[string]]::new()
$digests=[ordered]@{};$failures=[Collections.Generic.List[string]]::new()
foreach($case in @($corpus.positive)){
  try{
    $value=ConvertFrom-MIR4ApiV1Json -Json ([string]$case.input_json)
    Test-MIR4ApiV1Response $value|Out-Null
    $accepted.Add([string]$case.id);$digests[[string]$case.id]=[string]$value.digest
    if([string]$value.digest-cne[string]$case.digest-or(ConvertTo-MIR4ApiV1CanonicalJson $value)-cne[string]$case.canonical_json){$failures.Add("$($case.id):identity")}
  }catch{$failures.Add("$($case.id):$($_.Exception.Message)")}
}
foreach($case in @($corpus.negative)){
  try{$value=ConvertFrom-MIR4ApiV1Json -Json ([string]$case.input_json);Test-MIR4ApiV1Response $value|Out-Null;$failures.Add("$($case.id):accepted")}
  catch{$rejected.Add([string]$case.id);$code=$_.Exception.Message.Trim('[',']').Split(']')[0];if($code-cne[string]$case.diagnostic){$failures.Add("$($case.id):$code")}}
}
$results=[Collections.Generic.List[object]]::new()
$powerShell=[pscustomobject][ordered]@{schema=1;kind='MIR4SdkV1RuntimeConformanceResult';runtime='powershell';accepted=@($accepted);rejected=@($rejected);digests=$digests;failures=@($failures);passed=($failures.Count-eq0)}
$results.Add($powerShell)
$python=Get-Command python -ErrorAction SilentlyContinue
if($python){
  $previousBytecode=$env:PYTHONDONTWRITEBYTECODE
  $env:PYTHONDONTWRITEBYTECODE='1'
  try{$raw=& $python.Source (Join-Path $SdkRoot 'api-v1/python/mir4_api_v1.py') --conformance $corpusPath}
  finally{if($null-eq$previousBytecode){Remove-Item Env:PYTHONDONTWRITEBYTECODE -ErrorAction SilentlyContinue}else{$env:PYTHONDONTWRITEBYTECODE=$previousBytecode}}
  if($LASTEXITCODE-ne0){throw '[mir4-sdk-v1-python-conformance]'}
  $results.Add(($raw|ConvertFrom-Json -Depth 100))
}
$node=Get-Command node -ErrorAction SilentlyContinue
if(-not$node){
  foreach($candidate in @('C:\Program Files\nodejs\node.exe','C:\Program Files (x86)\nodejs\node.exe')){
    if(Test-Path -LiteralPath $candidate -PathType Leaf){$node=[pscustomobject]@{Source=$candidate};break}
  }
}
if($node){
  $raw=& $node.Source (Join-Path $SdkRoot 'api-v1/typescript/index.mjs') --conformance $corpusPath
  if($LASTEXITCODE-ne0){throw '[mir4-sdk-v1-node-conformance]'}
  $results.Add(($raw|ConvertFrom-Json -Depth 100))
}elseif($RequireNode){throw '[mir4-sdk-v1-node-required]'}
foreach($result in $results){
  if(-not[bool]$result.passed){throw "[mir4-sdk-v1-runtime-failed] $($result.runtime):$(@($result.failures)-join',')"}
  if((@($result.accepted)-join'|')-cne(@($powerShell.accepted)-join'|')-or(@($result.rejected)-join'|')-cne(@($powerShell.rejected)-join'|')){throw "[mir4-sdk-v1-accept-reject-drift] $($result.runtime)"}
  foreach($case in @($corpus.positive)){if([string]$result.digests.([string]$case.id)-cne[string]$case.digest){throw "[mir4-sdk-v1-digest-drift] $($result.runtime):$($case.id)"}}
}
$extension=Get-Content -Raw -LiteralPath (Join-Path $SdkRoot 'reference-extension-v1/extension.json')|ConvertFrom-Json -Depth 100
Test-MIR4ApiV1Extension -Extension $extension|Out-Null
[pscustomobject][ordered]@{schema=1;kind='MIR4SdkV1ConformanceResult';status='passed';positive=@($corpus.positive).Count;negative=@($corpus.negative).Count;runtimes=@($results.runtime);identical_accept_reject=$true;identical_digests=$true;package_visible=$false;publication_authorized=$false}|ConvertTo-Json -Depth 20 -Compress
