# MIR4-CANONICAL-EXECUTABLE-TEST
# Fixed maintenance assignment for the existing serial Black Glass worker.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$RepoRoot,
  [Parameter(Mandatory)][string]$OutputRoot,
  [Parameter(Mandatory)][string]$EngineRoot,
  [Parameter(Mandatory)][string]$LibraryRoot,
  [Parameter(Mandatory)][string]$Factorio210
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $RepoRoot 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $RepoRoot 'tools/lib/compatibility/FactorioRunner.ps1')
$baselinePath=Join-Path $RepoRoot 'fixtures/run-profiles/mir473-predecessor-inputs.json'
$baseline=Get-Content -LiteralPath $baselinePath -Raw|ConvertFrom-Json
$profile=Join-Path $RepoRoot 'fixtures/run-profiles/mir473-k2-f210.json'
$driver=Join-Path $RepoRoot 'tests/runtime/Test-MIR471EditionQualification.ps1'
$revision=(& git -C $RepoRoot rev-parse HEAD).Trim()
if((& git -C $RepoRoot rev-parse 'v4.7.2^{commit}').Trim()-cne$baseline.source_commit){throw 'Maintenance predecessor differs'}
& git -C $RepoRoot merge-base --is-ancestor $baseline.source_commit HEAD
if($LASTEXITCODE){throw 'Maintenance source is outside published lineage'}
$published=Join-Path $OutputRoot 'published-472'
[IO.Directory]::CreateDirectory($published)|Out-Null
& gh release download v4.7.2 --repo Julesc013/more-infinite-research --pattern '*.zip' --pattern SHA256SUMS.txt --dir $published
if($LASTEXITCODE){throw 'Published predecessor download failed'}
if((Get-FileHash (Join-Path $published 'SHA256SUMS.txt')).Hash-cne$baseline.checksum_sha256){throw 'Published checksum authority differs'}
$older=Join-Path $OutputRoot 'published-471'
[IO.Directory]::CreateDirectory($older)|Out-Null
& gh release download v4.7.1 --repo Julesc013/more-infinite-research --pattern $baseline.older_f210.filename --dir $older
if($LASTEXITCODE){throw 'Earlier data-only witness input download failed'}
if((Get-FileHash (Join-Path $older $baseline.older_f210.filename)).Hash-cne$baseline.older_f210.sha256){throw 'Earlier witness input differs'}

function Install-OwnArchive([string]$Path,[string]$Library){
  if(-not([IO.Path]::GetFileName($Path).StartsWith('more-infinite-research_'))){throw 'Only own player archives may be installed'}
  [IO.Directory]::CreateDirectory($Library)|Out-Null
  $lock=[IO.File]::Open((Join-Path $Library '.mir-library.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try{
    Assert-MIRLibraryIdle
    if(Test-Path -LiteralPath (Join-Path $Library '.mir-active-profile.json')){throw 'Unrestored direct library transaction'}
    $destination=Join-Path $Library ([IO.Path]::GetFileName($Path));$expected=(Get-FileHash $Path).Hash
    if(Test-Path -LiteralPath $destination){
      $prior=(Get-FileHash $destination).Hash
      if($prior-ceq$expected){return}
      $custody=Join-Path $env:LOCALAPPDATA ('MIRWorker/preserved/'+$prior)
      [IO.Directory]::CreateDirectory($custody)|Out-Null
      $saved=Join-Path $custody ([IO.Path]::GetFileName($Path))
      if(-not(Test-Path -LiteralPath $saved)){[IO.File]::Copy($destination,$saved,$false)}
      if((Get-FileHash $saved).Hash-cne$prior){throw 'Prior own archive custody differs'}
    }
    [IO.File]::Copy($Path,$destination,$true)
    if((Get-FileHash $destination).Hash-cne$expected){throw 'Installed own archive differs'}
  }finally{$lock.Dispose()}
}

$inputs=@()
foreach($target in @('f210','f200','f110','f100','f017','f016','f015','f014','f013')){
  $row=@($baseline.targets|Where-Object target -CEQ $target)
  if($row.Count-ne1){throw 'Missing exact target input'}
  $row=$row[0];$line=switch($target){f210{'2.1'};f200{'2.0'};f110{'1.1'};f100{'1.0'};default{'0.'+[int]$target.Substring(1)}}
  $engine=if($target-ceq'f210'){$Factorio210}else{Join-Path $EngineRoot ($line+'/bin/x64/factorio.exe')}
  $engineData=Join-Path (Split-Path (Split-Path (Split-Path $engine))) 'data'
  if(-not(Test-Path $engine)-or(Get-Content (Join-Path $engineData 'base/info.json') -Raw|ConvertFrom-Json).version-cne$row.minimum_base-or(Get-FileHash $engine).Hash-cne$row.engine_sha256){throw "Exact engine identity differs: $target"}
  $prior=Join-Path $published $row.filename
  if((Get-FileHash $prior).Hash-cne$row.sha256){throw "Published package differs: $target"}
  $library=if($target-cin@('f013','f014','f015','f016')){Join-Path $RepoRoot ('build/archive-libraries/'+$line)}else{Join-Path $LibraryRoot $line}
  $inputs+=@{target=$target;factorio_line=$line;engine=$engine;engine_sha256=$row.engine_sha256;engine_version=$row.minimum_base;library=$library;published_path=$prior;published_sha256=$row.sha256}
}
$inputs|ConvertTo-Json -Depth 8|Set-Content (Join-Path $OutputRoot 'native-inputs.json')
$f210=@($inputs|Where-Object target -CEQ f210)[0]
Install-OwnArchive $f210.published_path $f210.library
Install-OwnArchive (Join-Path $older $baseline.older_f210.filename) $f210.library

# The old package must fail for the reported reason, rather than an unrelated
# dependency, resource or fixture error. The runner always restores controls.
$oldOutput=Join-Path $OutputRoot 'old-fail'
$oldSucceeded=$false
try{
  & $driver -RepoRoot $RepoRoot -Target f210 -SourceVersion 4.7.2 -CandidateZip $f210.published_path -CandidateSha256 $f210.published_sha256 -PublishedZip (Join-Path $older $baseline.older_f210.filename) -PublishedSha256 $baseline.older_f210.sha256 -LibraryDirectory $f210.library -FactorioBin $f210.engine -OutputRoot $oldOutput -CandidateOnly -PlanetaryDataReproducer -ExternalProfilePath $profile -ExpectedPeakMemoryMiB 3072
  $oldSucceeded=$true
}catch{$oldError=[string]$_.Exception.Message}
if($oldSucceeded){throw 'Released 4.7.2 did not reproduce the expected failure'}
$oldLog=@(Get-ChildItem -LiteralPath $oldOutput -Filter factorio-current.log -File -Recurse)
$needle='MIR approved science binding is unresolved: planetary-data (ambiguous-approved-pack-source:planetary-data)'
if($oldLog.Count-ne1-or-not([IO.File]::ReadAllText($oldLog[0].FullName).Contains($needle))){throw "Old failure was not the reported planetary-data failure: $oldError"}
@{status='expected-negative';package_sha256=$f210.published_sha256;engine_sha256=$f210.engine_sha256;log=$oldLog[0].FullName;log_sha256=(Get-FileHash $oldLog[0].FullName).Hash;reason=$needle}|ConvertTo-Json|Set-Content (Join-Path $OutputRoot 'old-fail.json')

$packages=@()
foreach($targetInput in $inputs){
  $target=$targetInput.target
  if($target-cin@('f210','f200','f110','f100')){
    $record=New-MIR4TargetPackage -RepoRoot $RepoRoot -Target $target -CandidateId MIR473-FINAL -SourceVersion 4.7.3 -DistributionVersion ('4.7.'+$target.Substring(1)+'03') -OutputRoot (Join-Path $OutputRoot 'packages')
    $archive=[string]$record.archive_path;$hash=[string]$record.archive_sha256
  }else{
    $record=& (Join-Path $RepoRoot 'tools/commands/release/New-MIR42HistoricalPlaytestCandidate.ps1') -RepoRoot $RepoRoot -Target $target -CandidateId MIR473-FINAL -SourceVersion 4.7.3 -OutputRoot (Join-Path $OutputRoot ('packages/'+$target))
    $archive=Join-Path $RepoRoot ([string]$record.distribution.path);$hash=[string]$record.distribution.sha256
  }
  $record|ConvertTo-Json -Depth 60|Set-Content (Join-Path $OutputRoot ($target+'-package.json'))
  if((Get-FileHash $archive).Hash-cne$hash){throw 'Constructed archive identity differs'}
  Install-OwnArchive $archive $targetInput.library
  $packages+=@{target=$target;archive_path=$archive;archive_sha256=$hash;published_path=$targetInput.published_path;published_sha256=$targetInput.published_sha256;factorio_line=$targetInput.factorio_line;base_minimum=$targetInput.engine_version;engine=$targetInput.engine;library=$targetInput.library}
}
$packages|ConvertTo-Json -Depth 10|Set-Content (Join-Path $OutputRoot 'package-index.json')
$f210=@($packages|Where-Object target -CEQ f210)[0]
$common=@{RepoRoot=$RepoRoot;Target='f210';SourceVersion='4.7.3';CandidateZip=$f210.archive_path;CandidateSha256=$f210.archive_sha256;PublishedZip=$f210.published_path;PublishedSha256=$f210.published_sha256;LibraryDirectory=$f210.library;FactorioBin=$f210.engine}
& $driver @common -OutputRoot (Join-Path $OutputRoot 'new-pass') -CandidateOnly -PlanetaryDataReproducer -ExternalProfilePath $profile -ExpectedPeakMemoryMiB 3072
& $driver @common -OutputRoot (Join-Path $OutputRoot 'k2-load') -CandidateOnly -ExternalProfilePath $profile -ExpectedPeakMemoryMiB 3072
foreach($p in $packages){
  & $driver -RepoRoot $RepoRoot -Target $p.target -SourceVersion 4.7.3 -CandidateZip $p.archive_path -CandidateSha256 $p.archive_sha256 -PublishedZip $p.published_path -PublishedSha256 $p.published_sha256 -LibraryDirectory $p.library -FactorioBin $p.engine -OutputRoot (Join-Path $OutputRoot ('editions/'+$p.target))
}
& $driver @common -OutputRoot (Join-Path $OutputRoot 'f210-base') -CandidateOnly
& $driver @common -OutputRoot (Join-Path $OutputRoot 'k2-upgrade') -ExternalProfilePath $profile -ExpectedPeakMemoryMiB 3072
@{status='passed';source_commit=$revision;source_version='4.7.3';targets=@($packages.target);old_fail='old-fail.json';new_pass='new-pass';k2_load='k2-load';k2_upgrade='k2-upgrade';edition_results='editions';base_load='f210-base'}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $OutputRoot 'qualification-result.json')
