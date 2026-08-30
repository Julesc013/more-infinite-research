function Copy-MIR4SdkV1Value {
  param([Parameter(Mandatory)]$Value)
  return (($Value | ConvertTo-Json -Depth 100 -Compress) | ConvertFrom-Json -Depth 100)
}

function New-MIR4SdkV1ConformanceCorpus {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $positive = [Collections.Generic.List[object]]::new()
  $specs = @(
    @{id='available-basic';surface='query';target='f210';items=@([ordered]@{id='alpha';status='known'});limit=128;evidence=@('vector:basic')},
    @{id='pagination-first';surface='query';target='f210';items=@([ordered]@{id='alpha'},[ordered]@{id='beta'});limit=1;evidence=@('vector:page')},
    @{id='pagination-second';surface='query';target='f210';items=@([ordered]@{id='alpha'},[ordered]@{id='beta'});limit=1;cursor='1';evidence=@('vector:page')},
    @{id='explicit-unavailable';surface='observation';target='f012';items=@();availability='unavailable';reason='No admitted museum observation transport.';evidence=@('admission:blocked','target:f012')},
    @{id='unicode-nfc';surface='profile';target='f210';items=@([ordered]@{label="caf$([char]0x00e9)";nested=[ordered]@{alpha='α';emoji='🧪'}});limit=8;evidence=@('vector:unicode')},
    @{id='nested-values';surface='proof';target='f210';items=@([ordered]@{array=@(1,$true,$null,'x');object=[ordered]@{a=1;b=2}});limit=8;evidence=@('vector:nested')},
    @{id='explicit-null';surface='tooling';target='f210';items=@([ordered]@{optional=$null;available=$true});limit=8;evidence=@('vector:null')},
    @{id='extension-data';surface='host-manifest';target='f210';items=@();limit=8;evidence=@('vector:extension');extensions=@{'org.example.sdk'=[ordered]@{enabled=$true;version=1}}},
    @{id='target-f200';surface='release';target='f200';items=@([ordered]@{line='2.0'});limit=8;evidence=@('target:f200')},
    @{id='target-f110';surface='target-provider-abi';target='f110';items=@([ordered]@{disposition='conditional'});limit=8;evidence=@('target:f110')},
    @{id='continuity';surface='continuity-bundle';target='f210';items=@([ordered]@{state='preserved'});limit=8;evidence=@('vector:continuity')},
    @{id='multi-evidence';surface='observation';target='f210';items=@([ordered]@{id='one'},[ordered]@{id='two'});limit=8;evidence=@('evidence:a','evidence:b')}
  )
  foreach($spec in $specs) {
    $parameters = @{RepoRoot=$RepoRoot;Surface=$spec.surface;Target=$spec.target;Items=@($spec.items);Limit=$(if($spec.ContainsKey('limit')){[int]$spec.limit}else{128});Evidence=@($spec.evidence)}
    if($spec.ContainsKey('cursor')){$parameters.Cursor=[string]$spec.cursor}
    if($spec.ContainsKey('availability')){$parameters.Availability=[string]$spec.availability;$parameters.Reason=[string]$spec.reason}
    if($spec.ContainsKey('extensions')){$parameters.Extensions=$spec.extensions}
    $value = New-MIR4ApiV1Response @parameters
    $canonical = ConvertTo-MIR4ModuleCanonicalJson $value
    $positive.Add([pscustomobject][ordered]@{id=$spec.id;input_json=$canonical;canonical_json=$canonical;digest=[string]$value.digest})
  }

  $negative = [Collections.Generic.List[object]]::new()
  $base = ConvertFrom-MIR4CanonicalJsonTextV1 -Json ([string]$positive[0].input_json) | ConvertFrom-Json -Depth 100
  $addNegative = {
    param([string]$Id,[string]$Diagnostic,[scriptblock]$Mutate,[switch]$KeepDigest)
    $value=Copy-MIR4SdkV1Value $base
    &$Mutate $value
    if(-not$KeepDigest -and $value.PSObject.Properties.Name -contains 'digest'){$value.digest=Get-MIR4ModuleDigest $value}
    $negative.Add([pscustomobject][ordered]@{id=$Id;input_json=(ConvertTo-MIR4ModuleCanonicalJson $value);diagnostic=$Diagnostic})
  }
  &$addNegative 'missing-field' 'mir4-api-v1-schema' {param($v)$v.PSObject.Properties.Remove('source_identity')}
  &$addNegative 'wrong-kind' 'mir4-api-v1-schema' {param($v)$v.kind='MIR4ApiResponseV2'}
  &$addNegative 'unknown-surface' 'mir4-api-v1-surface' {param($v)$v.surface='unknown'}
  &$addNegative 'target-id' 'mir4-api-v1-target' {param($v)$v.target.id='F210'}
  &$addNegative 'factorio-line' 'mir4-api-v1-target' {param($v)$v.target.factorio_line='2'}
  &$addNegative 'empty-version' 'mir4-api-v1-version' {param($v)$v.versions.source=''}
  &$addNegative 'canonicalization' 'mir4-api-v1-canonicalization' {param($v)$v.canonicalization='mir-canonical-json-v0'}
  &$addNegative 'authority-boundary' 'mir4-api-v1-authority-boundary' {param($v)$v.mutation_authorized=$true}
  &$addNegative 'capability-order' 'mir4-api-v1-capability-order' {param($v)$v.capabilities=@('zeta.capability','alpha.capability')}
  &$addNegative 'availability' 'mir4-api-v1-availability' {param($v)$v.availability.status='unknown'}
  &$addNegative 'evidence-order' 'mir4-api-v1-evidence-order' {param($v)$v.availability.evidence=@('z:evidence','a:evidence')}
  &$addNegative 'page-limit' 'mir4-api-v1-page' {param($v)$v.page.limit=129}
  &$addNegative 'returned-count' 'mir4-api-v1-returned-count' {param($v)$v.page.returned=0}
  &$addNegative 'total-bound' 'mir4-api-v1-page' {param($v)$v.page.total=0}
  &$addNegative 'cursor' 'mir4-api-v1-cursor' {param($v)$v.page.next_cursor='not-a-cursor'}
  &$addNegative 'unavailable-has-data' 'mir4-api-v1-unavailable-is-not-zero' {param($v)$v.availability.status='unavailable'}
  &$addNegative 'extension-namespace' 'mir4-api-v1-extension-namespace' {param($v)$v.extensions=[pscustomobject]@{'Bad Namespace'=[pscustomobject]@{enabled=$true}}}
  &$addNegative 'digest-mismatch' 'mir4-api-v1-digest' {param($v)$v.digest='sha256:'+('0'*64)} -KeepDigest

  return [pscustomobject][ordered]@{
    schema=1;kind='MIR4SdkV1ConformanceCorpus';canonicalization='mir-canonical-json/1'
    positive=@($positive);negative=@($negative)
    requirements=[ordered]@{minimum_positive=12;minimum_negative=16;exact_accept_reject=$true;exact_canonical_bytes=$true;exact_digests=$true}
  }
}
