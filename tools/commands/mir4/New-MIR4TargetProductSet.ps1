param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [ValidateSet('all','f210','f200','f110','f100','f018','f017','f016','f015','f014','f013','f012','f011','f010','f009','f008','f007','f006')][string]$Target='all',
  [string]$OutputRoot='build/mir4/m4c02-target-products',
  [switch]$Check
)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
$authority=Get-MIR4TargetCompilerAuthority -RepoRoot $repo
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$output=Assert-MIR4DescendantPath -Root (Join-Path $repo 'build/mir4') -Path $output
$selected=@($authority.target_groups.targets|ForEach-Object{$_}|Where-Object{$Target-eq'all'-or$_-eq$Target})
$sourceCommit=(& git -C $repo rev-parse HEAD).Trim()
$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$packageSourceSha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo

$modern=@($selected|Where-Object{$_-in@('f210','f200','f110','f100')})
$modernResults=@{}
foreach($key in $modern){
  if($Check){continue}
  $modernResults[$key]=New-MIR4TargetPackage -RepoRoot $repo -Target $key -CandidateId 'M4C02-09-24H' -OutputRoot 'build/packages/target-products'
}
$historical=@($selected|Where-Object{$_-in@('f018','f017','f016','f015','f014','f013')})
foreach($key in $historical){
  & (Join-Path $repo 'tools/commands/release/New-MIR4HistoricalPrivateCandidate.ps1') -RepoRoot $repo -Target $key -Repetitions 3 -Check:$Check
}

$contracts=New-MIR4TargetContractSet -RepoRoot $repo
$rows=@()
foreach($contract in @($contracts.targets|Where-Object{$Target-eq'all'-or$_.target-eq$Target})){
  $key=[string]$contract.target;$version=[string]$contract.identity.distribution_version
  $sourceRoot=if($key-in@('f210','f200','f110','f100')){'canonical-materializer'}elseif($key-in@('f018','f017','f016','f015','f014','f013')){'build/mir4/historical-private'}else{''}
  if(-not$sourceRoot){
    $rows+=[ordered]@{target=$key;version=$version;state='BLOCKED_WITH_EVIDENCE';maturity=[string]$contract.maturity;target_disposition=[string]$contract.support_policy.disposition;facility='unsupported-with-evidence';missing=@($contract.inputs.missing);package=$null;source_version='4.0.0';candidate_id='M4C02-09-24H';source_commit=$sourceCommit;source_tree=$sourceTree;publication_authorized=$false}
    continue
  }
  $source=if($sourceRoot-eq'canonical-materializer'){if($Check){Join-Path $repo "build/packages/target-products/$key/M4C02-09-24H/more-infinite-research_$version.zip"}else{[string]$modernResults[$key].archive_path}}else{Join-Path $repo "$sourceRoot/distributions/more-infinite-research_$version.zip"}
  $destination=if($sourceRoot-eq'canonical-materializer'){$source}else{Join-Path $output "packages/more-infinite-research_$version.zip"}
  if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "[mir4-target-product-source] ${key}:$source"}
  if(-not$Check-and$sourceRoot-ne'canonical-materializer'){New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent)|Out-Null;[IO.File]::Copy($source,$destination,$true)}
  if(-not(Test-Path -LiteralPath $destination -PathType Leaf)){throw "[mir4-target-product-missing] $key"}
  $sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
  $destinationHash=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
  if($sourceHash-cne$destinationHash){throw "[mir4-target-product-copy] $key"}
  $rows+=[ordered]@{target=$key;version=$version;state='built-private-unqualified';maturity=[string]$contract.maturity;target_disposition=[string]$contract.support_policy.disposition;facility=$(if($key-in@('f018','f017','f016','f015','f014','f013')){'finite-substitute'}else{'adapted'});package=[ordered]@{path=[IO.Path]::GetRelativePath($repo,$destination).Replace('\','/');sha256=$destinationHash;bytes=(Get-Item -LiteralPath $destination).Length;package_root="more-infinite-research_$version"};source_version='4.0.0';candidate_id='M4C02-09-24H';source_commit=$sourceCommit;source_tree=$sourceTree;publication_authorized=$false}
}
$manifest=[pscustomobject][ordered]@{schema=1;kind='MIR4PrivateTargetProductSetV1';programme_id=[string]$authority.programme_id;candidate_id='M4C02-09-24H';source_version='4.0.0';source_commit=$sourceCommit;source_tree=$sourceTree;package_source_sha256=$packageSourceSha256;state=$(if(@($rows|Where-Object{$_.state-eq'BLOCKED_WITH_EVIDENCE'}).Count){'partial-with-bounded-blockers'}else{'built-private-unqualified'});targets=$rows;semantic_authority=$false;public_support_authorized=$false;signing_or_sealing_authorized=$false;source_frozen=$false;publication_authorized=$false;record_sha256=''}
$manifest.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $manifest
$providerMatrix=[pscustomobject][ordered]@{schema=1;kind='MIR4TargetProviderMatrixV1';programme_id=[string]$authority.programme_id;targets=@($contracts.targets|ForEach-Object{[ordered]@{target=[string]$_.target;identity=$_.identity;profile=$_.profile;provider_spec=$_.provider_spec}});semantic_authority=$false;publication_authorized=$false;record_sha256=''}
$providerMatrix.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $providerMatrix
$dispositionMatrix=[pscustomobject][ordered]@{schema=1;kind='MIR4TargetDispositionMatrixV1';programme_id=[string]$authority.programme_id;targets=@($contracts.targets|ForEach-Object{[ordered]@{target=[string]$_.target;maturity=[string]$_.maturity;mode=[string]$_.mode;support_policy=$_.support_policy;inputs=$_.inputs;facilities=$_.facilities}});public_support_authorized=$false;publication_authorized=$false;record_sha256=''}
$dispositionMatrix.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $dispositionMatrix
$records=[ordered]@{
  'MIR4_TARGET_PROVIDER_MATRIX.json'=$providerMatrix
  'MIR4_TARGET_DISPOSITION_MATRIX.json'=$dispositionMatrix
  'MIR4_PRIVATE_PACKAGE_MATRIX.json'=$manifest
}
foreach($entry in $records.GetEnumerator()){
  $path=Join-Path $output $entry.Key
  if($Check){
    $existing=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 50
    if(-not(Test-MIR4BootstrapRecordHash -Record $existing)-or(ConvertTo-MIR4BootstrapCanonicalJson $existing)-cne(ConvertTo-MIR4BootstrapCanonicalJson $entry.Value)){throw "[mir4-target-product-record-stale] $($entry.Key)"}
  }else{Write-MIR4BootstrapRecord -Path $path -Record $entry.Value}
}
$manifest|ConvertTo-Json -Depth 30
