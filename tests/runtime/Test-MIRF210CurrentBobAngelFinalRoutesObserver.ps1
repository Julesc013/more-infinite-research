# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$ExactStageRoot='C:\Projects\Factorio\more-infinite-research\build\tests\wed-material-f210\current-ba-20260930',
  [string]$OutputRoot='build/tests/f210-ba-final-routes-observer',
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

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$stage=(Resolve-Path -LiteralPath $ExactStageRoot).Path
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
Assert-Observer $output.StartsWith((Join-Path $repo 'build')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) 'output root must be inside build.'
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
$candidate=New-MIR4TargetPackage -RepoRoot $repo -Target f210 -CandidateId ('F210-CURRENT-BA-FINAL-ROUTES-OBSERVER-'+[guid]::NewGuid().ToString('N').Substring(0,8).ToUpperInvariant()) -SourceVersion '4.2.0' -DistributionVersion '4.2.21000' -OutputRoot 'build/tests/mir42-f210-current-ba-final-routes-observer/packages'
$candidateZip=(Resolve-Path -LiteralPath ([string]$candidate.archive_path)).Path
$sourceCommit=(& git -C $repo rev-parse HEAD).Trim();$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$prepared=[ordered]@{
  schema=1;kind='MIR4F210CurrentBobAngelFinalRoutesObservationV1';status='prepared'
  scope='Read-only current 2.1.20 exact Bob/Angel evidence capture for 22 candidate ordinary Angel finals. It cannot admit a route or make a compatibility or release claim.'
  source=[ordered]@{commit=$sourceCommit;tree=$sourceTree;package_source_sha256=Get-ObserverSha (Join-Path $repo 'source/package-source.json')}
  exact_stage=[ordered]@{path=$stage;engine_sha256=[string]$stageReceipt.engine_sha256;candidate_sha256=[string]$stageReceipt.candidate_sha256;save_sha256=[string]$stageReceipt.save_sha256;archives=$expectedArchives}
  candidate=Get-ObserverArtifact $candidateZip
  fixture=@('info.json','data-final-fixes.lua','control.lua'|ForEach-Object{Get-ObserverArtifact (Join-Path $fixture $_)})
  harness=Get-ObserverArtifact $PSCommandPath
  expected_candidate_count=22
  non_claims=@('No productivity route is admitted by this observer.','No progression, balance, compatibility, or release claim is made.','Every candidate remains withheld until an exact reviewed certificate is separately implemented.')
}
if($PrepareOnly){$prepared|ConvertTo-Json -Depth 12;return}

$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
Assert-Observer ((Get-ObserverSha $engine) -ceq [string]$stageReceipt.engine_sha256) 'engine bytes differ from exact stage receipt.'
$version=(& $engine --version | Out-String)
Assert-Observer ($LASTEXITCODE -eq 0 -and $version -match 'Version:\s+2[.]1[.]20') 'requires Factorio 2.1.20.'
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
$run=Join-Path $output ([guid]::NewGuid().ToString('N'));$mods=Join-Path $run 'mods';$userdata=Join-Path $run 'userdata';New-Item -ItemType Directory -Force -Path $mods,$userdata|Out-Null
Copy-Item -LiteralPath $candidateZip -Destination $mods
foreach($archiveName in $expectedArchives.Keys){Copy-Item -LiteralPath (Join-Path $stage (Join-Path 'mods' $archiveName)) -Destination $mods}
Publish-MIRModDirectoryArchive -Source $fixture -Name 'mir-fixture-assert-f210-current-bob-angel-final-routes-observer' -Version '0.1.0' -ModsDir $mods|Out-Null
$modNames=@('base','elevated-rails','quality','recycler','space-age','more-infinite-research')+@($expectedArchives.Keys|ForEach-Object {$_ -replace '_[0-9]+(?:[.][0-9]+)*[.]zip$',''})+@('mir-fixture-assert-f210-current-bob-angel-final-routes-observer')
@{mods=@($modNames|ForEach-Object{[ordered]@{name=$_;enabled=$true}})}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $mods 'mod-list.json') -Encoding utf8
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent)-Parent)-Parent
[IO.File]::WriteAllText((Join-Path $run 'config.ini'),"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($userdata.Replace('\','/'))`n",[Text.UTF8Encoding]::new($false))
$start=[Diagnostics.ProcessStartInfo]::new($engine);$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
foreach($argument in @('--config',(Join-Path $run 'config.ini'),'--no-log-rotation','--disable-audio','--mod-directory',$mods,'--create',(Join-Path $run 'observer.zip'))){[void]$start.ArgumentList.Add($argument)}
$process=[Diagnostics.Process]::Start($start)
try{$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();if(-not $process.WaitForExit(180000)){$process.Kill($true);throw "observer engine timed out: $run"};$engineText=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult();[IO.File]::WriteAllText((Join-Path $run 'engine.log'),$engineText,[Text.UTF8Encoding]::new($false));if($process.ExitCode -ne 0){throw "observer engine failed: $run`n$($engineText.Substring([Math]::Max(0,$engineText.Length-2500)))"}}finally{$process.Dispose()}
$factorioLog=Join-Path $userdata 'factorio-current.log';Assert-Observer (Test-Path -LiteralPath $factorioLog -PathType Leaf) 'Factorio log absent.'
$logText=Get-Content -LiteralPath $factorioLog -Raw
Assert-Observer ($logText.Contains('[mir-f210-current-ba-final-observer] RUNTIME PASS observer-has-no-gameplay-mutation')) 'runtime completion marker absent.'
$summary=[regex]::Match($logText,'\[mir-f210-current-ba-final-observer\] DATA PASS read-only-finalized-contract-capture candidates=(?<candidates>[0-9]+) observed=(?<observed>[0-9]+) missing=(?<missing>[0-9]+)')
Assert-Observer $summary.Success 'data completion marker absent.'
Assert-Observer ([int]$summary.Groups['candidates'].Value -eq 22) 'candidate count differs.'
$routes=@([regex]::Matches($logText,'\[mir-f210-current-ba-final-observer\] ROUTE recipe=(?<recipe>[^\s]+) .* status=(?<status>present|missing)')|ForEach-Object{[ordered]@{recipe=$_.Groups['recipe'].Value;status=$_.Groups['status'].Value}})
Assert-Observer ($routes.Count -eq 22) "expected 22 candidate route records; got $($routes.Count)."
$result=$prepared.Clone();$result.status='observed';$result.engine=[ordered]@{version=([regex]::Match($version,'Version:\s+[^\r\n]+').Value).Trim();executable_sha256=Get-ObserverSha $engine};$result.run_root=$run;$result.route_records=$routes;$result.summary=[ordered]@{observed=[int]$summary.Groups['observed'].Value;missing=[int]$summary.Groups['missing'].Value};$result.logs=[ordered]@{engine=Get-ObserverArtifact (Join-Path $run 'engine.log');factorio=Get-ObserverArtifact $factorioLog};$result|ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8;$result|ConvertTo-Json -Depth 16;Write-Output "Evidence: $run"
