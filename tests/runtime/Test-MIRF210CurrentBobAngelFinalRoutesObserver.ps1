# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$ExactStageRoot='C:\Projects\Factorio\more-infinite-research\build\tests\wed-material-f210\current-ba-20260930',
  [string]$OutputRoot='ba-final',
  [string]$RecoverRunRoot='',
  [switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Assert-Observer([bool]$Condition,[string]$Message) {
  if(-not $Condition){throw "F210 current Bob/Angel final-routes observer: $Message"}
}
function Get-ObserverSha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Get-ObserverArtifact([string]$Path){
  $item=Get-Item -LiteralPath $Path -ErrorAction Stop
  [ordered]@{path=$item.FullName;bytes=[int64]$item.Length;sha256=Get-ObserverSha $item.FullName}
}
function Get-ObserverProjectRoot([string]$RepoRoot){
  $record=@(& git -C $RepoRoot worktree list --porcelain | Where-Object {$_ -like 'worktree *'} | Select-Object -First 1)
  Assert-Observer ($record.Count -eq 1) 'cannot establish the primary project worktree.'
  (Resolve-Path -LiteralPath $record[0].Substring(9)).Path
}
function Get-ObserverZipInfo([string]$Archive){
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
  try {
    $entries=@($zip.Entries | Where-Object {$_.FullName -match '(^|/)info[.]json$'})
    Assert-Observer ($entries.Count -eq 1) "expected one info.json entry: $Archive"
    $reader=[IO.StreamReader]::new($entries[0].Open())
    try {$text=$reader.ReadToEnd()} finally {$reader.Dispose()}
    $info=$text|ConvertFrom-Json
    Assert-Observer ([string]$info.factorio_version -ceq '2.1') "archive factorio_version differs from 2.1: $Archive"
    [ordered]@{name=[string]$info.name;entry=$entries[0].FullName;entry_count=$zip.Entries.Count}
  } finally {$zip.Dispose()}
}
function Assert-ObserverArchivePaths([string]$Archive,[string]$ModsDirectory){
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip=[IO.Compression.ZipFile]::OpenRead($Archive);$longest=0
  try {
    foreach($entry in @($zip.Entries)){
      Assert-Observer (-not [IO.Path]::IsPathRooted($entry.FullName) -and $entry.FullName -notmatch '(^|/)[.][.](/|$)') "unsafe archive entry: $Archive::$($entry.FullName)"
      $staged=[IO.Path]::GetFullPath((Join-Path $ModsDirectory $entry.FullName))
      $longest=[Math]::Max($longest,$staged.Length)
      Assert-Observer ($staged.Length -lt 240) "staged archive entry path reaches 240 characters: $staged"
    }
  } finally {$zip.Dispose()}
  $longest
}
function Assert-ObserverFixturePaths([string]$Fixture,[string]$ModsDirectory){
  $root=Join-Path $ModsDirectory 'mir-fixture-assert-f210-current-bob-angel-final-routes-observer_0.1.0';$longest=0
  foreach($file in Get-ChildItem -LiteralPath $Fixture -File -Recurse){
    $relative=$file.FullName.Substring($Fixture.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $staged=[IO.Path]::GetFullPath((Join-Path $root $relative));$longest=[Math]::Max($longest,$staged.Length)
    Assert-Observer ($staged.Length -lt 240) "staged fixture path reaches 240 characters: $staged"
  }
  $longest
}

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$stage=(Resolve-Path -LiteralPath $ExactStageRoot).Path
$project=Get-ObserverProjectRoot $repo
$projectBuild=Join-Path $project 'build'
$output=if([IO.Path]::IsPathRooted($OutputRoot)){[IO.Path]::GetFullPath($OutputRoot)}else{[IO.Path]::GetFullPath((Join-Path (Join-Path $projectBuild 'tests') $OutputRoot))}
Assert-Observer $output.StartsWith($projectBuild+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) 'output root must be inside the primary project build tree.'
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') | Out-Host
$sourceChanges=@(& git -C $repo status --porcelain --untracked-files=all -- source)
Assert-Observer ($sourceChanges.Count -eq 0) "refuses changed package source: $($sourceChanges -join '; ')"
$fixture=Join-Path $repo 'fixtures/assert-f210-current-bob-angel-final-routes-observer'
foreach($path in @($fixture,(Join-Path $fixture 'info.json'),(Join-Path $fixture 'data-final-fixes.lua'),(Join-Path $fixture 'control.lua'))){Assert-Observer (Test-Path -LiteralPath $path) "fixture path absent: $path"}
$stageReceipt=Get-Content -LiteralPath (Join-Path $stage 'result.json') -Raw | ConvertFrom-Json
Assert-Observer ([string]$stageReceipt.engine_sha256 -ceq 'E4B1FDBDCC77F4C3449318CE1398493EA7A8E77A19D68BD1AC3A858D0F373B92') 'exact stage engine hash differs.'
$expectedArchives=[ordered]@{
  'boblibrary_3.0.1.zip'='3DD83A195E120BAECC51A43B0B3EB965C0D419A09883F9DAA018B3921C12D51B'
  'bobores_3.0.0.zip'='7F8E33E35F59BB3F2CD72E3AB2FED30D1C2AE9C117E3731324AC307D9965082B'
  'bobplates_3.0.2.zip'='0C9A4910E2DCAA8DCABBE5BFFA67333F214EAB2EFD8C798D5EF84D90B691862D'
  'bobelectronics_3.0.1.zip'='50C2718E38D507CF4D4ACA2DBFE3240997172309413397C9C70083BBAE6927BE'
  'bobtech_3.0.0.zip'='397D979976316C3CE082D2AD29A046CCBAA147E412A0AEB727230BDECF665E5B'
  'angelsrefining_2.1.2.zip'='AF5E79E35E591F68D52F13EDA082950E10AC98A4B7722B3F568D0211E3FEB813'
  'angelsrefininggraphics_2.1.0.zip'='79F373BC628F619EDE3B1875827172390D2C3F5EAB56310F6F1572C4553CB6EF'
  'angelspetrochem_2.1.3.zip'='95FA8F1740A180E5CF5617EFDA7C409A7974E29B236F9F5AB28D789193AC44B4'
  'angelspetrochemgraphics_2.1.0.zip'='DECDC2FCD5BBBDEF70784943C142C30FAA7294B98E814296C5D44D09A9DE4790'
  'angelssmelting_2.1.1.zip'='1DFCDD77D075FD545CFEE74BD8A6443E7E90B133D3832FDD47649C84892243A9'
  'angelssmeltinggraphics_2.1.1.zip'='71E89ABF7CC372FADE39B11FB4FE83A1B5E629226AF123BFE8DDA08C7C228DD3'
}
$stageArchives=@{};foreach($row in @($stageReceipt.mods)){$stageArchives[[string]$row.archive]=[string]$row.sha256}
Assert-Observer ($stageArchives.Count -eq $expectedArchives.Count) 'exact stage archive count differs.'
foreach($entry in $expectedArchives.GetEnumerator()){
  Assert-Observer ($stageArchives.ContainsKey($entry.Key) -and $stageArchives[$entry.Key] -ceq $entry.Value) "stage receipt archive differs: $($entry.Key)"
  $archive=Join-Path $stage (Join-Path 'mods' $entry.Key)
  Assert-Observer (Test-Path -LiteralPath $archive -PathType Leaf) "stage archive absent: $($entry.Key)"
  Assert-Observer ((Get-ObserverSha $archive) -ceq $entry.Value) "stage archive bytes differ: $($entry.Key)"
}

. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
$candidateOutput=Join-Path $projectBuild 'tests/mir42-f210-current-ba-final-routes-observer/packages'
$candidate=New-MIR4TargetPackage -RepoRoot $repo -Target f210 -CandidateId ('F210-CURRENT-BA-FINAL-ROUTES-OBSERVER-'+[guid]::NewGuid().ToString('N').Substring(0,8).ToUpperInvariant()) -SourceVersion '4.2.0' -DistributionVersion '4.2.21000' -OutputRoot $candidateOutput
$candidateZip=(Resolve-Path -LiteralPath ([string]$candidate.archive_path)).Path
$sourceCommit=(& git -C $repo rev-parse HEAD).Trim();$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$fixtureText=Get-Content -LiteralPath (Join-Path $fixture 'data-final-fixes.lua') -Raw
Assert-Observer $fixtureText.Contains('[mir-f210-current-ba-final-observer] DATA PASS read-only-finalized-contract-capture') 'fixture data marker differs.'
Assert-Observer $fixtureText.Contains('RETURN_PATH_EDGE target=') 'fixture Gold return-path witness is absent.'
$fixtureInfo=Get-Content -LiteralPath (Join-Path $fixture 'info.json') -Raw | ConvertFrom-Json
Assert-Observer ([string]$fixtureInfo.factorio_version -ceq '2.1') 'fixture factorio_version differs from 2.1.'
$modNames=@('base','elevated-rails','quality','recycler','space-age','more-infinite-research')+@($expectedArchives.Keys|ForEach-Object {$_ -replace '_[0-9]+(?:[.][0-9]+)*[.]zip$',''})+@('mir-fixture-assert-f210-current-bob-angel-final-routes-observer')
Assert-Observer ((@($modNames|Sort-Object -Unique)).Count -eq $modNames.Count) 'mod list contains duplicate names.'
$plannedMods=Join-Path (Join-Path $output ('path-check-'+('0'*32))) 'mods'
$archives=@($candidateZip)+@($expectedArchives.Keys|ForEach-Object {Join-Path $stage (Join-Path 'mods' $_)})
$archiveMetadata=@();$longestPath=0
foreach($archive in $archives){
  $metadata=Get-ObserverZipInfo $archive
  Assert-Observer ($modNames -contains $metadata.name) "archive is not enabled by the mod list: $($metadata.name)"
  $archiveMetadata+=$metadata
  $longestPath=[Math]::Max($longestPath,(Assert-ObserverArchivePaths $archive $plannedMods))
}
Assert-Observer ($archiveMetadata.Count -eq ($expectedArchives.Count+1)) 'staged archive count differs.'
$longestPath=[Math]::Max($longestPath,(Assert-ObserverFixturePaths $fixture $plannedMods))
$prepared=[ordered]@{
  schema=1;kind='MIR4F210CurrentBobAngelFinalRoutesObservationV1';status='prepared'
  scope='Read-only current 2.1.20 exact Bob/Angel evidence capture for 22 candidate ordinary Angel finals. It cannot admit a route or make a compatibility or release claim.'
  source=[ordered]@{commit=$sourceCommit;tree=$sourceTree;package_source_sha256=Get-ObserverSha (Join-Path $repo 'source/package-source.json')}
  exact_stage=[ordered]@{path=$stage;engine_sha256=[string]$stageReceipt.engine_sha256;candidate_sha256=[string]$stageReceipt.candidate_sha256;save_sha256=[string]$stageReceipt.save_sha256;archives=$expectedArchives}
  candidate=Get-ObserverArtifact $candidateZip
  fixture=@('info.json','data-final-fixes.lua','control.lua'|ForEach-Object{Get-ObserverArtifact (Join-Path $fixture $_)})
  harness=Get-ObserverArtifact $PSCommandPath
  expected_candidate_count=22
  staging_preflight=[ordered]@{project_build=$projectBuild;planned_mods=$plannedMods;archive_count=$archiveMetadata.Count;longest_staged_path=$longestPath;max_path_exclusive=240;factorio_version='2.1';fixture_marker='DATA PASS read-only-finalized-contract-capture';mod_list=$modNames}
  non_claims=@('No productivity route is admitted by this observer.','No progression, balance, compatibility, or release claim is made.','Every candidate remains withheld until an exact reviewed certificate is separately implemented.')
}
if($PrepareOnly){$prepared|ConvertTo-Json -Depth 12;return}

$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
Assert-Observer ((Get-ObserverSha $engine) -ceq [string]$stageReceipt.engine_sha256) 'engine bytes differ from exact stage receipt.'
$version=(& $engine --version | Out-String)
Assert-Observer ($LASTEXITCODE -eq 0 -and $version -match 'Version:\s+2[.]1[.]20') 'requires Factorio 2.1.20.'
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
if(-not $RecoverRunRoot){
$run=Join-Path $output ([guid]::NewGuid().ToString('N'));$mods=Join-Path $run 'mods';$userdata=Join-Path $run 'userdata';New-Item -ItemType Directory -Force -Path $mods,$userdata|Out-Null
Copy-MIRFileWithHardlinkFallback -Source $candidateZip -Destination (Join-Path $mods ([IO.Path]::GetFileName($candidateZip)))
foreach($archiveName in $expectedArchives.Keys){Copy-MIRFileWithHardlinkFallback -Source (Join-Path $stage (Join-Path 'mods' $archiveName)) -Destination (Join-Path $mods $archiveName)}
Publish-MIRModDirectoryArchive -Source $fixture -Name 'mir-fixture-assert-f210-current-bob-angel-final-routes-observer' -Version '0.1.0' -ModsDir $mods|Out-Null
@{mods=@($modNames|ForEach-Object{[ordered]@{name=$_;enabled=$true}})}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $mods 'mod-list.json') -Encoding utf8
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent)-Parent)-Parent
[IO.File]::WriteAllText((Join-Path $run 'config.ini'),"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($userdata.Replace('\','/'))`n",[Text.UTF8Encoding]::new($false))
$start=[Diagnostics.ProcessStartInfo]::new($engine);$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
foreach($argument in @('--config',(Join-Path $run 'config.ini'),'--no-log-rotation','--disable-audio','--mod-directory',$mods,'--create',(Join-Path $run 'observer.zip'))){[void]$start.ArgumentList.Add($argument)}
$process=[Diagnostics.Process]::Start($start)
try{$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();if(-not $process.WaitForExit(180000)){$process.Kill($true);throw "observer engine timed out: $run"};$engineText=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult();[IO.File]::WriteAllText((Join-Path $run 'engine.log'),$engineText,[Text.UTF8Encoding]::new($false));if($process.ExitCode -ne 0){throw "observer engine failed: $run`n$($engineText.Substring([Math]::Max(0,$engineText.Length-2500)))"}}finally{$process.Dispose()}
}else{
  $run=(Resolve-Path -LiteralPath $RecoverRunRoot).Path
  Assert-Observer $run.StartsWith($output+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) 'recovery run must remain under the selected output root.'
  Assert-Observer (-not ((Get-Item -LiteralPath $run -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) 'recovery run may not be a reparse point.'
  $mods=Join-Path $run 'mods';$userdata=Join-Path $run 'userdata'
  $stagedCandidate=Join-Path $mods ([IO.Path]::GetFileName($candidateZip))
  Assert-Observer ((Test-Path -LiteralPath $stagedCandidate -PathType Leaf) -and (Get-ObserverSha $stagedCandidate) -ceq $prepared.candidate.sha256) 'recovery candidate does not match current source materialization.'
  foreach($archiveName in $expectedArchives.Keys){$path=Join-Path $mods $archiveName;Assert-Observer ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-ObserverSha $path) -ceq $expectedArchives[$archiveName]) "recovery dependency differs: $archiveName"}
  Assert-Observer (Test-Path -LiteralPath (Join-Path $run 'observer.zip') -PathType Leaf) 'recovery save is absent.'
  Assert-Observer (Test-Path -LiteralPath (Join-Path $run 'engine.log') -PathType Leaf) 'recovery engine log is absent.'
  $prepared.candidate=Get-ObserverArtifact $stagedCandidate
}
$factorioLog=Join-Path $userdata 'factorio-current.log';Assert-Observer (Test-Path -LiteralPath $factorioLog -PathType Leaf) 'Factorio log absent.'
$logText=Get-Content -LiteralPath $factorioLog -Raw
Assert-Observer ($logText.Contains('[mir-f210-current-ba-final-observer] RUNTIME PASS observer-has-no-gameplay-mutation')) 'runtime completion marker absent.'
$summary=[regex]::Match($logText,'\[mir-f210-current-ba-final-observer\] DATA PASS read-only-finalized-contract-capture candidates=(?<candidates>[0-9]+) observed=(?<observed>[0-9]+) missing=(?<missing>[0-9]+)')
Assert-Observer $summary.Success 'data completion marker absent.'
Assert-Observer ([int]$summary.Groups['candidates'].Value -eq 22) 'candidate count differs.'
$frontier=[regex]::Match($logText,'\[mir-f210-current-ba-final-observer\] SCIENCE_FRONTIER PASS packs=(?<packs>[0-9]+) early_present=(?<early>[0-9]+)')
Assert-Observer $frontier.Success 'science-frontier completion marker absent.'
$goldPath=[regex]::Match($logText,'\[mir-f210-current-ba-final-observer\] RETURN_PATH target=angels-liquid-molten-gold start=item:bob-gold-plate status=witnessed edges=(?<edges>[0-9]+)')
Assert-Observer $goldPath.Success 'Gold return-path witness marker absent.'
$goldEdges=@([regex]::Matches($logText,'\[mir-f210-current-ba-final-observer\] RETURN_PATH_EDGE target=angels-liquid-molten-gold step=(?<step>[0-9]+)/(?<count>[0-9]+) from=(?<from>[^\s]+) to=(?<to>[^\s]+) recipe=(?<recipe>[^\s]+) variant=(?<variant>[0-9]+) source=(?<source>[^\s]+) hidden=(?<hidden>[^\s]+) enabled_without_research=(?<enabled_without_research>[^\s]+) variant_hidden=(?<variant_hidden>[^\s]+) variant_enabled=(?<variant_enabled>[^\s]+) productivity=(?<productivity>[^\s]+) declared_productivity=(?<declared_productivity>[^\s]+) variant_productivity=(?<variant_productivity>[^\s]+) inputs=(?<inputs>[^\s]+) results=(?<results>[^\s]+)')|ForEach-Object{[ordered]@{step=[int]$_.Groups['step'].Value;count=[int]$_.Groups['count'].Value;from=$_.Groups['from'].Value;to=$_.Groups['to'].Value;recipe=$_.Groups['recipe'].Value;variant=[int]$_.Groups['variant'].Value;source=$_.Groups['source'].Value;hidden=$_.Groups['hidden'].Value;enabled_without_research=$_.Groups['enabled_without_research'].Value;variant_hidden=$_.Groups['variant_hidden'].Value;variant_enabled=$_.Groups['variant_enabled'].Value;productivity=$_.Groups['productivity'].Value;declared_productivity=$_.Groups['declared_productivity'].Value;variant_productivity=$_.Groups['variant_productivity'].Value;inputs=$_.Groups['inputs'].Value;results=$_.Groups['results'].Value}})
Assert-Observer ($goldEdges.Count -eq [int]$goldPath.Groups['edges'].Value -and $goldEdges.Count -gt 0) 'Gold return-path edge count differs.'
Assert-Observer ($goldEdges[0].from -ceq 'item:bob-gold-plate' -and $goldEdges[$goldEdges.Count-1].to -ceq 'fluid:angels-liquid-molten-gold') 'Gold return-path witness endpoints differ.'
$goldBindings=@{}
foreach($match in [regex]::Matches($logText,'\[mir-f210-current-ba-final-observer\] BINDING recipe=(?<recipe>[^\s]+) owners=(?<owners>[^\s]+) unlocks=(?<unlocks>[^\r\n]+)')){$goldBindings[$match.Groups['recipe'].Value]=[ordered]@{owners=$match.Groups['owners'].Value;unlocks=$match.Groups['unlocks'].Value}}
for($index=0;$index -lt $goldEdges.Count;$index++){$edge=$goldEdges[$index];Assert-Observer ($edge.step -eq ($index+1) -and $edge.count -eq $goldEdges.Count) 'Gold return-path step sequence differs.';if($index -gt 0){Assert-Observer ($goldEdges[$index-1].to -ceq $edge.from) 'Gold return-path edge identities are disconnected.'};Assert-Observer $goldBindings.ContainsKey([string]$edge.recipe) "Gold path recipe binding absent: $($edge.recipe)";$edge['owners']=$goldBindings[[string]$edge.recipe].owners;$edge['unlocks']=$goldBindings[[string]$edge.recipe].unlocks}
$routes=@([regex]::Matches($logText,'\[mir-f210-current-ba-final-observer\] ROUTE recipe=(?<recipe>[^\s]+) .* status=(?<status>present|missing)')|ForEach-Object{[ordered]@{recipe=$_.Groups['recipe'].Value;status=$_.Groups['status'].Value}})
Assert-Observer ($routes.Count -eq 22) "expected 22 candidate route records; got $($routes.Count)."
$result=[ordered]@{};foreach($key in $prepared.Keys){$result[$key]=$prepared[$key]};$result.status='observed';$result.engine=[ordered]@{version=([regex]::Match($version,'Version:\s+[^\r\n]+').Value).Trim();executable_sha256=Get-ObserverSha $engine};$result.run_root=$run;$result.recovered_from_completed_engine_run=[bool]$RecoverRunRoot;$result.route_records=$routes;$result.gold_return_path=[ordered]@{target='angels-liquid-molten-gold';start='item:bob-gold-plate';edge_count=$goldEdges.Count;edges=$goldEdges};$result.summary=[ordered]@{observed=[int]$summary.Groups['observed'].Value;missing=[int]$summary.Groups['missing'].Value;science_frontier_packs=[int]$frontier.Groups['packs'].Value;science_frontier_early_present=[int]$frontier.Groups['early'].Value};$result.logs=[ordered]@{engine=Get-ObserverArtifact (Join-Path $run 'engine.log');factorio=Get-ObserverArtifact $factorioLog};$result|ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8;$result|ConvertTo-Json -Depth 16;Write-Output "Evidence: $run"
