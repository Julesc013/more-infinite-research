# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$ExactStageRoot='C:\Projects\Factorio\more-infinite-research\build\tests\wed-material-f210\current-ba-20260930',
  [string[]]$LocalModLibraryDirs=@('C:\Projects\Factorio\testmods\2.1'),
  [string]$OutputRoot='build/p/f210-ba-tin-observer',
  [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB=0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120,
  [switch]$PrepareOnly,
  [string]$AuditLogPath='',
  [string[]]$ExpectedInputRecipes=@('angels-plate-tin','angels-plate-tin-2')
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Assert-Observer([bool]$Condition,[string]$Message) {
  if (-not $Condition) { throw "F210 current Bob/Angel Tin observer: $Message" }
}
function Get-ObserverSha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Get-ObserverArtifact([string]$Path) {
  $item=Get-Item -LiteralPath $Path -ErrorAction Stop
  [ordered]@{path=$item.FullName;bytes=[int64]$item.Length;sha256=Get-ObserverSha $item.FullName}
}
function Get-ObserverInputContracts {
  param([AllowEmptyCollection()][object[]]$AuditRows,[string[]]$ExpectedRecipes)
  Assert-Observer ($ExpectedRecipes.Count -gt 0 -and @($ExpectedRecipes | Sort-Object -Unique).Count -eq $ExpectedRecipes.Count) 'expected input recipes must be nonempty and unique.'
  $rows=@($AuditRows | Where-Object { $_.PSObject.Properties['kind'] -and $_.kind -ceq 'material_route_certificate' })
  Assert-Observer (@($rows | Where-Object { $_.PSObject.Properties['status'] -and $_.status -ceq 'incomplete' }).Count -eq 0) 'input capture is incomplete.'
  foreach($recipe in $ExpectedRecipes | Sort-Object) {
    $matches=@($rows | Where-Object { $_.PSObject.Properties['recipe'] -and $_.recipe -ceq $recipe })
    Assert-Observer ($matches.Count -eq 1) "expected one input contract for $recipe; got $($matches.Count)."
    $row=$matches[0]
    foreach($field in @('schema','binding_schema','phase','status','canonical_risk_fingerprint','return_graph_fingerprint','bindings_fingerprint','reachable_identity_count','relevant_recipe_count','direct_output_producer_count')) {
      Assert-Observer ($null -ne $row.PSObject.Properties[$field]) "missing input field $field for $recipe."
    }
    Assert-Observer ($row.schema -ceq '1' -and $row.binding_schema -ceq '2' -and $row.phase -ceq 'input' -and $row.status -ceq 'observed') "wrong input phase, binding schema or status for $recipe."
    foreach($field in @('canonical_risk_fingerprint','return_graph_fingerprint','bindings_fingerprint')) {
      Assert-Observer ([string]$row.$field -cmatch '^mir32-[0-9a-f]{8}$') "invalid input fingerprint $field for $recipe."
    }
    $counts=@{}
    foreach($field in @('reachable_identity_count','relevant_recipe_count','direct_output_producer_count')) {
      $number=0
      Assert-Observer ([int]::TryParse([string]$row.$field,[ref]$number) -and $number -gt 0) "invalid input count $field for $recipe."
      $counts[$field]=$number
    }
    [pscustomobject][ordered]@{schema=2;recipe=$recipe;phase='input';canonical_risk_fingerprint=[string]$row.canonical_risk_fingerprint;return_graph_fingerprint=[string]$row.return_graph_fingerprint;bindings_fingerprint=[string]$row.bindings_fingerprint;reachable_identity_count=$counts.reachable_identity_count;relevant_recipe_count=$counts.relevant_recipe_count;direct_output_producer_count=$counts.direct_output_producer_count}
  }
}
function Parse-ObserverRoute([string]$Line) {
  $match=[regex]::Match($Line,'recipe=(?<recipe>[^\s]+) generic=(?<generic>true|false) reason=(?<reason>[^\s]+) source=(?<source>[^\s]+) hidden=(?<hidden>true|false) declared_productivity=(?<declared>true|false) effective_productivity=(?<effective>true|false) maximum_productivity=(?<maximum>[^\s]+) risk=(?<risk>mir32-[0-9a-f]{8}) graph=(?<graph>mir32-[0-9a-f]{8}) bindings=(?<bindings>mir32-[0-9a-f]{8}) identities=(?<identities>[0-9]+) recipes=(?<recipes>[0-9]+) producers=(?<producers>[0-9]+) inputs=(?<inputs>[^\s]+) results=(?<results>[^\s]+)')
  Assert-Observer $match.Success "malformed ROUTE observation: $Line"
  [ordered]@{
    recipe=$match.Groups['recipe'].Value;generic=($match.Groups['generic'].Value -ceq 'true');reason=$match.Groups['reason'].Value
    source=$match.Groups['source'].Value;hidden=($match.Groups['hidden'].Value -ceq 'true')
    declared_productivity=($match.Groups['declared'].Value -ceq 'true');effective_productivity=($match.Groups['effective'].Value -ceq 'true')
    maximum_productivity=[double]$match.Groups['maximum'].Value;risk_fingerprint=$match.Groups['risk'].Value
    return_graph_fingerprint=$match.Groups['graph'].Value;bindings_fingerprint=$match.Groups['bindings'].Value
    reachable_identity_count=[int]$match.Groups['identities'].Value;relevant_recipe_count=[int]$match.Groups['recipes'].Value
    direct_output_producer_count=[int]$match.Groups['producers'].Value;inputs=$match.Groups['inputs'].Value;results=$match.Groups['results'].Value
  }
}

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/compatibility/DiagnosticsParser.ps1')
if($AuditLogPath) {
  $auditPath=(Resolve-Path -LiteralPath $AuditLogPath).Path
  $contracts=@(Get-ObserverInputContracts -AuditRows @(Read-MIRAuditLog -Path $auditPath) -ExpectedRecipes $ExpectedInputRecipes)
  [ordered]@{schema=1;kind='MIR4MaterialRouteInputObservationReadbackV1';status='observed';scope='Diagnostic input-record readback only; no route admission or native qualification.';audit=Get-ObserverArtifact $auditPath;input_contracts=$contracts} | ConvertTo-Json -Depth 8
  return
}
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 3 -MaxEntriesPerRoot 400 -MaxWorktrees 8 -MaxBranches 32 | Out-Host
# Admission precedes stage resolution, materialization and every engine call,
# including PrepareOnly. AuditLogPath above remains a read-only replay path.
$resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
Assert-MIR441CleanTrackedSource -RepoRoot $repo
$stage=(Resolve-Path -LiteralPath $ExactStageRoot).Path
$fixture=Join-Path $repo 'fixtures/assert-f210-current-bob-angel-tin-route-observer'
foreach($path in @($fixture,(Join-Path $fixture 'info.json'),(Join-Path $fixture 'settings-updates.lua'),(Join-Path $fixture 'data-final-fixes.lua'),(Join-Path $fixture 'control.lua'))) { Assert-Observer (Test-Path -LiteralPath $path) "fixture path absent: $path" }
$receiptPath=Join-Path $stage 'result.json'
$receipt=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
Assert-Observer ([string]$receipt.engine_sha256 -ceq 'E4B1FDBDCC77F4C3449318CE1398493EA7A8E77A19D68BD1AC3A858D0F373B92') 'exact stage engine hash differs.'
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
$stageArchives=@{};foreach($row in @($receipt.mods)) { $stageArchives[[string]$row.archive]=[string]$row.sha256 }
Assert-Observer ($stageArchives.Count -eq $expectedArchives.Count) 'exact stage archive count differs.'
foreach($entry in $expectedArchives.GetEnumerator()) {
  Assert-Observer ($stageArchives.ContainsKey($entry.Key) -and $stageArchives[$entry.Key] -ceq $entry.Value) "stage receipt archive differs: $($entry.Key)"
}
$dependencyInputs=Resolve-MIRNativeProbeDependencyInputs -StageRoot $stage -ExpectedArchives $expectedArchives -LocalModLibraryDirs $LocalModLibraryDirs

$run=$resources.root
New-Item -ItemType Directory -Path $run | Out-Null
$candidate=New-MIRNativeProbeTargetPackage -Context $resources -RepoRoot $repo
$candidateZip=(Resolve-Path -LiteralPath ([string]$candidate.archive_path)).Path
$sourceCommit=(& git -C $repo rev-parse HEAD).Trim();$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$prepared=[ordered]@{schema=1;kind='MIR4F210CurrentBobAngelTinRouteObservationV1';status='prepared';scope='Current 2.1.20 exact Bob/Angel Tin contract capture with diagnostic setting enabled; no route admission or gameplay mutation.';source=[ordered]@{commit=$sourceCommit;tree=$sourceTree;package_source_sha256=Get-ObserverSha (Join-Path $repo 'source/package-source.json')};exact_stage=[ordered]@{path=$stage;engine_sha256=[string]$receipt.engine_sha256;candidate_sha256=[string]$receipt.candidate_sha256;save_sha256=[string]$receipt.save_sha256;archives=$expectedArchives};candidate=Get-ObserverArtifact $candidateZip;fixture=@('info.json','settings-updates.lua','data-final-fixes.lua','control.lua'|ForEach-Object{Get-ObserverArtifact (Join-Path $fixture $_)});harness=Get-ObserverArtifact $PSCommandPath;non_claims=@('No productivity route is admitted by this observer.','No progression, balance, compatibility or release claim is made.','The prior 2.1.17 combined-Tin diagnostic remains a separate lock.')}
$prepared['dependency_inputs']=@($dependencyInputs.Values|ForEach-Object{[ordered]@{archive=$_.file_name;source=Get-ObserverArtifact $_.source_path;provenance_kind=$_.provenance_kind}})
$prepared['resource_policy']=[ordered]@{declared_peak_memory_mib=$ExpectedPeakMemoryMiB;max_new_output_mib=$MaxNewOutputMiB;memory_enforcement='sampled-watchdog-not-hard-cap'}
if($PrepareOnly) {$prepared['resource_runs']=$resources.runs.ToArray();Write-MIRNativeProbeResult -Context $resources -Record $prepared;$prepared|ConvertTo-Json -Depth 16;return}

$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
Assert-Observer ((Get-ObserverSha $engine) -ceq [string]$receipt.engine_sha256) 'engine bytes differ from exact stage receipt.'
$versionRun=Invoke-MIRNativeProbeProcess -Context $resources -FilePath $engine -Arguments @('--version') -TimeoutSeconds 30
$version=Get-Content -LiteralPath $versionRun.stdout -Raw
Assert-Observer ($version -match 'Version:\s+2[.]1[.]20') 'requires Factorio 2.1.20.'
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
$leaseRoot=Join-Path $run 'stage';$mods=Join-Path $leaseRoot 'mods';$userdata=Join-Path $run 'userdata';New-Item -ItemType Directory -Path $leaseRoot,$userdata|Out-Null
$inputs=@([ordered]@{source_path=$candidateZip;file_name=[IO.Path]::GetFileName($candidateZip);expected_sha256=Get-ObserverSha $candidateZip;role='candidate';identity=[ordered]@{target='f210';source_version='4.2.1';distribution_version='4.2.21001'};provenance=[ordered]@{kind='canonical-materializer';source_commit=$sourceCommit;source_tree=$sourceTree};immutable=$true})
foreach($archiveName in $expectedArchives.Keys) {
  $selected=$dependencyInputs[$archiveName]
  $inputs+=@([ordered]@{source_path=$selected.source_path;file_name=$archiveName;expected_sha256=$expectedArchives[$archiveName];role='dependency-mod';identity=[ordered]@{archive=$archiveName;sha256=$expectedArchives[$archiveName]};provenance=[ordered]@{kind=$selected.provenance_kind;receipt_sha256=Get-ObserverSha $receiptPath};immutable=$true})
}
$lease=$null
try {
$lease=New-MIRImmutableInputLease -RunRoot $leaseRoot -StageDirectory $mods -Inputs $inputs -RequireHardLinks
Add-MIRNativeProbeImmutableLease -Context $resources -Lease $lease
Publish-MIRModDirectoryArchive -Source $fixture -Name 'mir-fixture-assert-f210-current-bob-angel-tin-route-observer' -Version '0.1.0' -ModsDir $mods|Out-Null
$modNames=@('base','elevated-rails','quality','recycler','space-age','more-infinite-research')+@($expectedArchives.Keys|ForEach-Object { $_ -replace '_[0-9]+(?:[.][0-9]+)*[.]zip$','' })+@('mir-fixture-assert-f210-current-bob-angel-tin-route-observer')
@{mods=@($modNames|ForEach-Object{[ordered]@{name=$_;enabled=$true}})}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $mods 'mod-list.json') -Encoding utf8
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent)-Parent)-Parent
[IO.File]::WriteAllText((Join-Path $run 'config.ini'),"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($userdata.Replace('\','/'))`n",[Text.UTF8Encoding]::new($false))
$engineRun=Invoke-MIRNativeProbeProcess -Context $resources -FilePath $engine -TimeoutSeconds 120 `
 -Arguments @('--config',(Join-Path $run 'config.ini'),'--no-log-rotation','--disable-audio','--mod-directory',$mods,'--create',(Join-Path $run 'observer.zip'))
$factorioLog=Join-Path $userdata 'factorio-current.log';Assert-Observer (Test-Path -LiteralPath $factorioLog -PathType Leaf) 'Factorio log absent.'
$logText=Get-Content -LiteralPath $factorioLog -Raw
$prepared['input_contracts']=@(Get-ObserverInputContracts -AuditRows @(Read-MIRAuditLog -Path $factorioLog) -ExpectedRecipes $ExpectedInputRecipes)
Assert-Observer ($logText.Contains('[mir-f210-current-ba-tin-observer] DATA PASS read-only-finalized-contract-capture')) 'data completion marker absent.'
Assert-Observer ($logText.Contains('[mir-f210-current-ba-tin-observer] RUNTIME PASS observer-has-no-gameplay-mutation')) 'runtime completion marker absent.'
$active=@([regex]::Matches($logText,'\[mir-f210-current-ba-tin-observer\] ACTIVE_MODS (?<mods>[^\r\n]+)'))
Assert-Observer ($active.Count -eq 1) "expected one active-mod record; got $($active.Count)."
$routeLines=@([regex]::Matches($logText,'\[mir-f210-current-ba-tin-observer\] ROUTE (?<record>[^\r\n]+)')|ForEach-Object{$_.Groups['record'].Value})
Assert-Observer ($routeLines.Count -eq 3) "expected three exact route records; got $($routeLines.Count)."
$routes=@($routeLines|ForEach-Object{Parse-ObserverRoute $_}|Sort-Object { $_['recipe'] })
Assert-Observer ((@($routes.recipe)-join ',') -ceq 'angels-plate-tin,angels-plate-tin-2,bob-tin-plate') 'route set differs.'
foreach($route in $routes) { Assert-Observer ($route.risk_fingerprint -match '^mir32-[0-9a-f]{8}$' -and $route.return_graph_fingerprint -match '^mir32-[0-9a-f]{8}$' -and $route.bindings_fingerprint -match '^mir32-[0-9a-f]{8}$') "invalid exact fingerprint record: $($route.recipe)" }
$generated=@([regex]::Matches($logText,'\[mir-f210-current-ba-tin-observer\] GENERATED early=(?<early>recipe-prod-research_material_tin-1:3) continuation=(?<continuation>withheld:no_reachable_late_science_frontier) recipes=(?<recipes>angels-plate-tin,angels-plate-tin-2)'))
Assert-Observer ($generated.Count -eq 1) "expected one exact Tin staged-generation record; got $($generated.Count)."
$result=$prepared.Clone();$result.status='observed';$result.engine=[ordered]@{version=([regex]::Match($version,'Version:\s+[^\r\n]+').Value).Trim();executable_sha256=Get-ObserverSha $engine};$result.run_root=$run;$result.active_mods=$active[0].Groups['mods'].Value;$result.routes=$routes;$result.generated=[ordered]@{early=$generated[0].Groups['early'].Value;continuation=$generated[0].Groups['continuation'].Value;recipes=$generated[0].Groups['recipes'].Value};$result.logs=[ordered]@{stdout=Get-ObserverArtifact $engineRun.stdout;stderr=Get-ObserverArtifact $engineRun.stderr;factorio=Get-ObserverArtifact $factorioLog};$result.resource_runs=$resources.runs.ToArray()
$result['input_lease']=Complete-MIRImmutableInputLease -Lease $lease -Outcome passed
$lease=$null
Write-MIRNativeProbeResult -Context $resources -Record $result
$result|ConvertTo-Json -Depth 30
Write-Output "Evidence: $run"
} catch {
  $failure=$_
  try {
    Write-MIRNativeProbeResult -Context $resources -Record ([ordered]@{status='failed';scope='Tin diagnostic capture; no route admission';error=$failure.Exception.Message;resource_runs=$resources.runs.ToArray()})
  } catch {
    Write-Warning "Failed capture result could not be retained within its output budget: $($_.Exception.Message). Owned process ledgers remain in $run."
  }
  throw $failure
} finally {
  if($null -ne $lease -and -not $lease.closed) { $null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed }
}
