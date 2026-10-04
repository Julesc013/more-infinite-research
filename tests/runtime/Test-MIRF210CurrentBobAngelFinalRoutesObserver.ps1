# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$ExactStageRoot='C:\Projects\Factorio\more-infinite-research\build\tests\wed-material-f210\current-ba-20260930',
  [string]$OutputRoot='build/p/f210-ba-final-observer',
  [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB=0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120,
  [string]$RecoverRunRoot='',
  [string]$AuditLogPath='',
  [switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Assert-Observer([bool]$Condition,[string]$Message) {
  if(-not $Condition){throw "F210 current Bob/Angel final-routes observer: $Message"}
}
function Get-ObserverSha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Get-ObserverMaterialOutcomeInventory([string]$LogText){
  Assert-Observer ($LogText.Length -le 33554432) 'inventory log exceeds the 32 MiB text budget.'
  $prefix='(?m)\[mir-material-outcome-inventory\] '
  $lineEnd='(?=\r?$)'
  $endings=@([regex]::Matches($LogText,$prefix+'PASS complete=true phase=finalized-raw-prototypes subjects=17 recipes=(?<recipes>[0-9]+) results=(?<results>[0-9]+) gaps=(?<gaps>[0-9]+) acquisition=false admission=false'+$lineEnd))
  Assert-Observer ($endings.Count -eq 1) 'inventory needs one complete finalized marker without admission.'
  $subjects=@([regex]::Matches($LogText,$prefix+'SUBJECT id=(?<id>[^\s]+) status=(?<status>prototype-absent|no-observed-producer|observed) items=(?<items>[0-9]+) producers=(?<producers>[0-9]+)'+$lineEnd))
  $expected=@('aluminium/plate','gold/plate','lead/plate','nickel/plate','platinum/plate','silver/plate','tin/plate','titanium/plate','copper-tungsten/alloy','zinc/plate','bronze/alloy','brass/alloy','gunmetal/alloy','invar/alloy','cobalt-steel/alloy','nitinol/alloy','platinum/wire')
  Assert-Observer ($subjects.Count -eq $expected.Count) 'independent subject inventory is incomplete or duplicated.'
  $items=@([regex]::Matches($LogText,$prefix+'ITEM subject=(?<subject>[^\s]+) name=(?<name>[^\s]+) hidden=(?<hidden>true|false)'+$lineEnd))
  $producers=@([regex]::Matches($LogText,$prefix+'PRODUCER subject=(?<subject>[^\s]+) recipe=(?<recipe>[^\s]+) hidden=(?<hidden>true|false) enabled=(?<enabled>true|false) productivity=(?<productivity>unspecified|true|false)'+$lineEnd))
  $gaps=@([regex]::Matches($LogText,$prefix+'GAP subject=(?<subject>[^\s]+) recipe=(?<recipe>[^\s]+)'+$lineEnd))
  Assert-Observer ($items.Count -le 34 -and $producers.Count -le 60000 -and $gaps.Count -le 60000) 'inventory row budget exceeded.'
  $protocolCount=[regex]::Matches($LogText,'\[mir-material-outcome-inventory\]').Count
  Assert-Observer ($protocolCount -eq ($endings.Count+$subjects.Count+$items.Count+$producers.Count+$gaps.Count)) 'inventory contains an unrecognized or malformed protocol record.'
  $records=[Collections.Generic.List[object]]::new()
  foreach($id in $expected){
    $matches=@($subjects|Where-Object {$_.Groups['id'].Value -ceq $id})
    Assert-Observer ($matches.Count -eq 1) "expected one subject $id."
    $subject=$matches[0];$itemRows=@($items|Where-Object {$_.Groups['subject'].Value -ceq $id});$producerRows=@($producers|Where-Object {$_.Groups['subject'].Value -ceq $id})
    Assert-Observer ($itemRows.Count -eq [int]$subject.Groups['items'].Value -and $producerRows.Count -eq [int]$subject.Groups['producers'].Value) "inventory counts differ for $id."
    $itemNames=@($itemRows|ForEach-Object {[Uri]::UnescapeDataString($_.Groups['name'].Value)})
    $recipeNames=@($producerRows|ForEach-Object {[Uri]::UnescapeDataString($_.Groups['recipe'].Value)})
    $family,$shape=$id.Split('/')
    $aliases=if($shape -ceq 'wire'){@('angels-wire-platinum')}elseif($shape -ceq 'plate'){@("bob-$family-plate","angels-plate-$family")}elseif($family -ceq 'copper-tungsten'){@('bob-copper-tungsten-alloy')}else{@("bob-$family-alloy","angels-plate-$family")}
    foreach($itemName in $itemNames){Assert-Observer ($itemName -cin $aliases) "wrong output shape or alias for $id."}
    $uniqueItems=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $uniqueRecipes=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($itemName in $itemNames){Assert-Observer ($uniqueItems.Add($itemName)) "duplicate inventory identities for $id."}
    foreach($recipeName in $recipeNames){Assert-Observer ($uniqueRecipes.Add($recipeName)) "duplicate inventory identities for $id."}
    $status=$subject.Groups['status'].Value
    $expectedStatus=if($itemRows.Count -eq 0){'prototype-absent'}elseif($producerRows.Count -eq 0){'no-observed-producer'}else{'observed'}
    Assert-Observer ($status -ceq $expectedStatus) "inventory status differs for $id."
    $records.Add([ordered]@{id=$id;status=$status;items=@($itemRows|ForEach-Object {[ordered]@{name=[Uri]::UnescapeDataString($_.Groups['name'].Value);hidden=$_.Groups['hidden'].Value -ceq 'true'}});producers=@($producerRows|ForEach-Object {[ordered]@{recipe=[Uri]::UnescapeDataString($_.Groups['recipe'].Value);hidden=$_.Groups['hidden'].Value -ceq 'true';enabled_without_research=$_.Groups['enabled'].Value -ceq 'true';declared_productivity=$_.Groups['productivity'].Value}})})
  }
  foreach($entry in @($items)+@($producers)+@($gaps)){Assert-Observer ($entry.Groups['subject'].Value -cin $expected) 'inventory row names an unknown subject.'}
  $producerIdentities=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($record in $records){foreach($producer in $record.producers){$null=$producerIdentities.Add($record.id+"`0"+$producer.recipe)}}
  $gapIdentities=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($gap in $gaps){
    $id=$gap.Groups['subject'].Value;$recipe=[Uri]::UnescapeDataString($gap.Groups['recipe'].Value)
    Assert-Observer ($gapIdentities.Add($id+"`0"+$recipe)) 'duplicate observation gap.'
    Assert-Observer ($producerIdentities.Contains($id+"`0"+$recipe)) 'gap recipe is outside the independent denominator.'
  }
  $observedRoutes=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($route in [regex]::Matches($LogText,'\[mir-f210-current-ba-final-observer\] ROUTE recipe=(?<recipe>[^\s]+) ')){
    Assert-Observer ($observedRoutes.Add($route.Groups['recipe'].Value)) 'duplicate finalized route observation.'
  }
  foreach($record in $records){foreach($producer in $record.producers){
    $isGap=$gapIdentities.Contains($record.id+"`0"+$producer.recipe)
    Assert-Observer ($isGap -eq (-not $observedRoutes.Contains($producer.recipe))) 'observation gap does not match the independent producer denominator.'
  }}
  Assert-Observer ($gaps.Count -eq [int]$endings[0].Groups['gaps'].Value -and [int]$endings[0].Groups['recipes'].Value -le 10000 -and [int]$endings[0].Groups['results'].Value -le 60000) 'inventory completion totals differ or exceed their budget.'
  [ordered]@{schema=1;kind='MIRMaterialOutcomeInventoryObservationV1';status='observed';phase='finalized-raw-prototypes';complete=$true;subjects=$records.ToArray();observation_gaps=@($gaps|ForEach-Object {[ordered]@{subject=$_.Groups['subject'].Value;recipe=[Uri]::UnescapeDataString($_.Groups['recipe'].Value)}});acquisition_proved=$false;admission_granted=$false}
}
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
    [ordered]@{name=[string]$info.name;version=[string]$info.version;entry=$entries[0].FullName;entry_count=$zip.Entries.Count}
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

function Get-ObserverCompletedRecovery {
  param([string]$RunRoot,[string]$OutputRoot,$Source,[string]$Fixture,[string]$HarnessPath,[string]$StageReceiptPath,$ExpectedArchives,[string]$Engine)
  $run=Resolve-MIR441RecoveryScratchPath -Path ([IO.Path]::GetFullPath($RunRoot))
  $output=Resolve-MIR441RecoveryScratchPath -Path ([IO.Path]::GetFullPath($OutputRoot))
  Assert-Observer (Test-MIR441PathContained -Root $output -Path $run) 'recovery run must remain under the selected output root.'
  $receiptPath=Join-Path $run 'result.json'
  $receiptFile=Get-Item -LiteralPath $receiptPath -ErrorAction Stop
  Assert-Observer ($receiptFile.Length -le 32MB) 'recovery receipt exceeds 32 MiB.'
  $json=Get-Content -LiteralPath $receiptPath -Raw
  $jsonArguments=@{AsHashtable=$true;Depth=30}
  $preservesDateStrings=(Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')
  if($preservesDateStrings){$jsonArguments.DateKind='String'}
  $record=$json|ConvertFrom-Json @jsonArguments
  Assert-Observer ($record.schema -eq 2 -and $record.kind -ceq 'MIR4F210CurrentBobAngelFinalRoutesObservationV1' -and $record.status -ceq 'observed') 'recovery requires a completed governed observation; historical and incomplete rows remain preserved.'
  foreach($name in @('commit','tree','package_source_sha256','source_version','distribution_version')) {Assert-Observer ($record.source[$name] -ceq $Source[$name]) "recovery source fingerprint differs: $name"}
  Assert-Observer ($record.run_root -ceq $run -and $record.harness.sha256 -ceq (Get-ObserverSha $HarnessPath)) 'recovery run or harness fingerprint differs.'
  Assert-Observer ($record.exact_stage.receipt_sha256 -ceq (Get-ObserverSha $StageReceiptPath) -and $record.exact_stage.engine_sha256 -ceq (Get-ObserverSha $Engine)) 'recovery stage or engine fingerprint differs.'
  Assert-Observer ($record.engine.executable_sha256 -ceq $record.exact_stage.engine_sha256 -and $record.engine.version -match '^Version:\s+2[.]1[.]20(?:\s|$)') 'recovery engine identity differs.'
  Assert-Observer ($record.fixture.Count -eq 4) 'recovery fixture inventory differs.'
  foreach($name in @('info.json','data-final-fixes.lua','control.lua','material-outcome-inventory.lua')) {
    $path=Join-Path $Fixture $name;$rows=@($record.fixture|Where-Object {$_.path -ceq $path})
    Assert-Observer ($rows.Count -eq 1 -and $rows[0].sha256 -ceq (Get-ObserverSha $path)) "recovery fixture differs: $name"
  }
  if(-not $preservesDateStrings){
    # Older PowerShell parses ISO date strings as DateTime and can trim their
    # trailing zeros. Restore the three canonical lease timestamps exactly.
    $document=[Text.Json.JsonDocument]::Parse($json)
    try{foreach($name in @('started_utc','receipt_captured_utc','completed_utc')){$record.input_lease[$name]=$document.RootElement.GetProperty('input_lease').GetProperty($name).GetString()}}finally{$document.Dispose()}
  }
  $null=Assert-MIRImmutableInputTerminalReceipt -Receipt $record.input_lease
  Assert-Observer ($record.input_lease.require_hard_links -and $record.input_lease.inputs.Count -eq ($ExpectedArchives.Count+1)) 'recovery requires complete strict input custody.'
  Assert-Observer (Test-MIR441PathContained -Root $run -Path $record.candidate.path) 'recovery candidate escaped its run.'
  $expected=[ordered]@{};foreach($entry in $ExpectedArchives.GetEnumerator()) {$expected[$entry.Key]=$entry.Value}
  $expected[[IO.Path]::GetFileName($record.candidate.path)]=$record.candidate.sha256
  foreach($entry in $expected.GetEnumerator()) {
    $rows=@($record.input_lease.inputs|Where-Object {$_.file_name -ceq $entry.Key})
    Assert-Observer ($rows.Count -eq 1 -and $rows[0].expected_sha256 -ceq $entry.Value -and $rows[0].staging_mode -ceq 'hardlink') "recovery leased input differs: $($entry.Key)"
    $row=$rows[0];$staged=Resolve-MIR441RecoveryScratchPath -Path $row.stage_path
    Assert-Observer ($staged -ceq (Join-Path $run (Join-Path 'stage/mods' $entry.Key))) 'recovery staged input escaped its exact mod directory.'
    if($entry.Key -ceq [IO.Path]::GetFileName($record.candidate.path)){Assert-Observer ($row.source_path -ceq $record.candidate.path) 'recovery candidate differs from its leased source.'}
    Assert-Observer ((Get-ObserverSha $row.source_path) -ceq $entry.Value -and (Get-ObserverSha $staged) -ceq $entry.Value -and (Get-MIRImmutableInputFileIdentity $row.source_path) -ceq (Get-MIRImmutableInputFileIdentity $staged)) "recovery input custody changed: $($entry.Key)"
  }
  $candidateInfo=Get-ObserverZipInfo $record.candidate.path
  Assert-Observer ($candidateInfo.name -ceq 'more-infinite-research' -and $candidateInfo.version -ceq '4.2.21001') 'recovery candidate version differs.'
  Assert-Observer ($record.resource_runs.Count -eq 3) 'recovery process inventory differs.'
  $index=0
  foreach($actor in $record.resource_runs) {
    $index++
    Assert-Observer ($actor.index -eq $index -and $actor.status -ceq 'passed' -and $actor.result.passed -and $actor.result.exit_code -eq 0) 'recovery process did not complete successfully or has a duplicated identity.'
    $suffixes=@{ledger='.resources.jsonl';stdout='.stdout.txt';stderr='.stderr.txt'}
    foreach($name in @('ledger','stdout','stderr')) {
      $path=Resolve-MIR441RecoveryScratchPath -Path $actor[$name]
      Assert-Observer ($path -ceq (Join-Path $run ("process-$index"+$suffixes[$name])) -and (Test-Path -LiteralPath $path -PathType Leaf)) 'recovery process evidence is absent or escaped its run.'
    }
  }
  Assert-Observer ($record.logs.Count -eq 3 -and $record.logs.factorio.path -ceq (Join-Path $run 'userdata/factorio-current.log') -and $record.logs.stdout.path -ceq $record.resource_runs[2].stdout -and $record.logs.stderr.path -ceq $record.resource_runs[2].stderr) 'recovery log inventory differs.'
  foreach($log in $record.logs.Values) {
    $path=Resolve-MIR441RecoveryScratchPath -Path $log.path
    Assert-Observer ((Test-MIR441PathContained -Root $run -Path $path) -and (Get-Item -LiteralPath $path).Length -eq $log.bytes -and $log.bytes -le 32MB -and (Get-ObserverSha $path) -ceq $log.sha256) 'recovery log custody differs or exceeds its budget.'
  }
  $save=$record.save
  Assert-Observer ($save.path -ceq (Join-Path $run 'observer.zip') -and (Get-Item -LiteralPath $save.path).Length -eq $save.bytes -and (Get-ObserverSha $save.path) -ceq $save.sha256) 'recovery save custody differs.'
  return $record
}

if(-not [string]::IsNullOrWhiteSpace($AuditLogPath)){
  $audit=Get-Item -LiteralPath $AuditLogPath -ErrorAction Stop
  Assert-Observer ($audit.Length -le 33554432) 'inventory audit file exceeds 32 MiB.'
  $inventory=Get-ObserverMaterialOutcomeInventory (Get-Content -Raw -LiteralPath $audit.FullName)
  [ordered]@{status='observed';audit_only=$true;native_engine_executed=$false;log=[ordered]@{path=$audit.FullName;bytes=$audit.Length;sha256=Get-ObserverSha $audit.FullName};material_outcomes=$inventory}|ConvertTo-Json -Depth 12
  return
}
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
$output=if([IO.Path]::IsPathRooted($OutputRoot)){[IO.Path]::GetFullPath($OutputRoot)}else{[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))}
$resources=$null;$lease=$null
if(-not $RecoverRunRoot){
  & (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 3 -MaxEntriesPerRoot 400 -MaxWorktrees 8 -MaxBranches 32 | Out-Host
  # This precedes stage resolution, materialization and all engine calls.
  $resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $output -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
}
Assert-MIR441CleanTrackedSource -RepoRoot $repo
$stage=(Resolve-Path -LiteralPath $ExactStageRoot).Path
$projectBuild=Join-Path $repo 'build'
$fixture=Join-Path $repo 'fixtures/assert-f210-current-bob-angel-final-routes-observer'
foreach($path in @($fixture,(Join-Path $fixture 'info.json'),(Join-Path $fixture 'data-final-fixes.lua'),(Join-Path $fixture 'control.lua'))){Assert-Observer (Test-Path -LiteralPath $path) "fixture path absent: $path"}
$stageReceiptPath=Join-Path $stage 'result.json'
$stageReceipt=Get-Content -LiteralPath $stageReceiptPath -Raw | ConvertFrom-Json
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
  if(-not $RecoverRunRoot){
    Assert-Observer (Test-Path -LiteralPath $archive -PathType Leaf) "stage archive absent: $($entry.Key)"
    Assert-Observer ((Get-ObserverSha $archive) -ceq $entry.Value) "stage archive bytes differ: $($entry.Key)"
  }
}

$sourceCommit=(& git -C $repo rev-parse HEAD).Trim();$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$source=[ordered]@{commit=$sourceCommit;tree=$sourceTree;package_source_sha256=Get-ObserverSha (Join-Path $repo 'source/package-source.json');source_version='4.2.1';distribution_version='4.2.21001'}
try {
if($RecoverRunRoot){
  Assert-Observer (-not $PrepareOnly) 'recovery and PrepareOnly are mutually exclusive.'
  $engine=(Resolve-Path -LiteralPath $FactorioBin).Path
  $prepared=Get-ObserverCompletedRecovery -RunRoot $RecoverRunRoot -OutputRoot $output -Source $source -Fixture $fixture -HarnessPath $PSCommandPath -StageReceiptPath $stageReceiptPath -ExpectedArchives $expectedArchives -Engine $engine
  $run=$prepared.run_root;$candidateZip=$prepared.candidate.path;$version=$prepared.engine.version
  $factorioLog=$prepared.logs.factorio.path
}else{
  $run=$resources.root
  New-Item -ItemType Directory -Path $run | Out-Null
  $candidate=New-MIRNativeProbeTargetPackage -Context $resources -RepoRoot $repo -CandidatePrefix 'F210-CURRENT-BA-FINAL-ROUTES-OBSERVER'
  $candidateZip=(Resolve-Path -LiteralPath ([string]$candidate.archive_path)).Path
$fixtureText=Get-Content -LiteralPath (Join-Path $fixture 'data-final-fixes.lua') -Raw
Assert-Observer $fixtureText.Contains('[mir-f210-current-ba-final-observer] DATA PASS read-only-finalized-contract-capture') 'fixture data marker differs.'
Assert-Observer $fixtureText.Contains('RETURN_PATH_EDGE target=') 'fixture Gold return-path witness is absent.'
Assert-Observer $fixtureText.Contains('VISIBLE_RETURN recipe=') 'fixture visible-return observation is absent.'
$fixtureInfo=Get-Content -LiteralPath (Join-Path $fixture 'info.json') -Raw | ConvertFrom-Json
Assert-Observer ([string]$fixtureInfo.factorio_version -ceq '2.1') 'fixture factorio_version differs from 2.1.'
$modNames=@('base','elevated-rails','quality','recycler','space-age','more-infinite-research')+@($expectedArchives.Keys|ForEach-Object {$_ -replace '_[0-9]+(?:[.][0-9]+)*[.]zip$',''})+@('mir-fixture-assert-f210-current-bob-angel-final-routes-observer')
Assert-Observer ((@($modNames|Sort-Object -Unique)).Count -eq $modNames.Count) 'mod list contains duplicate names.'
$plannedMods=Join-Path $run 'stage/mods'
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
  schema=2;kind='MIR4F210CurrentBobAngelFinalRoutesObservationV1';status='prepared'
  scope='Read-only current 2.1.20 Bob/Angel evidence capture for 22 candidate Angel finals. The visible-ordinary return view excludes player-usable generated recycling recipes and cannot establish route safety.'
  source=$source
  exact_stage=[ordered]@{path=$stage;receipt_sha256=Get-ObserverSha $stageReceiptPath;engine_sha256=[string]$stageReceipt.engine_sha256;candidate_sha256=[string]$stageReceipt.candidate_sha256;save_sha256=[string]$stageReceipt.save_sha256;archives=$expectedArchives}
  candidate=Get-ObserverArtifact $candidateZip
  fixture=@('info.json','data-final-fixes.lua','control.lua','material-outcome-inventory.lua'|ForEach-Object{Get-ObserverArtifact (Join-Path $fixture $_)})
  harness=Get-ObserverArtifact $PSCommandPath
  expected_candidate_count=22
  staging_preflight=[ordered]@{project_build=$projectBuild;planned_mods=$plannedMods;archive_count=$archiveMetadata.Count;longest_staged_path=$longestPath;max_path_exclusive=240;factorio_version='2.1';fixture_marker='DATA PASS read-only-finalized-contract-capture';mod_list=$modNames}
  non_claims=@('No productivity route is admitted by this observer.','Visible ordinary return absence does not establish safety: player-usable generated recycling recipes are excluded from that view.','No progression, balance, compatibility, or release claim is made.','Every candidate remains withheld until an exact reviewed certificate is separately implemented.')
}
Assert-Observer ($archiveMetadata[0].name -ceq 'more-infinite-research' -and $archiveMetadata[0].version -ceq '4.2.21001') 'candidate distribution version differs.'
$prepared['resource_policy']=[ordered]@{declared_peak_memory_mib=$ExpectedPeakMemoryMiB;max_new_output_mib=$MaxNewOutputMiB;memory_enforcement='sampled-watchdog-not-hard-cap'}
if($PrepareOnly){$prepared['resource_runs']=$resources.runs.ToArray();Write-MIRNativeProbeResult -Context $resources -Record $prepared;$prepared|ConvertTo-Json -Depth 16;return}

$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
Assert-Observer ((Get-ObserverSha $engine) -ceq [string]$stageReceipt.engine_sha256) 'engine bytes differ from exact stage receipt.'
$versionRun=Invoke-MIRNativeProbeProcess -Context $resources -FilePath $engine -Arguments @('--version') -TimeoutSeconds 30
$version=Get-Content -LiteralPath $versionRun.stdout -Raw
Assert-Observer ($version -match 'Version:\s+2[.]1[.]20') 'requires Factorio 2.1.20.'
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
$leaseRoot=Join-Path $run 'stage';$mods=Join-Path $leaseRoot 'mods';$userdata=Join-Path $run 'userdata'
New-Item -ItemType Directory -Path $leaseRoot,$userdata|Out-Null
$inputs=@([ordered]@{source_path=$candidateZip;file_name=[IO.Path]::GetFileName($candidateZip);expected_sha256=Get-ObserverSha $candidateZip;role='candidate';identity=[ordered]@{target='f210';source_version='4.2.1';distribution_version='4.2.21001'};provenance=[ordered]@{kind='canonical-materializer';source_commit=$sourceCommit;source_tree=$sourceTree};immutable=$true})
foreach($archiveName in $expectedArchives.Keys){
  $inputs+=@([ordered]@{source_path=Join-Path $stage (Join-Path 'mods' $archiveName);file_name=$archiveName;expected_sha256=$expectedArchives[$archiveName];role='dependency-mod';identity=[ordered]@{archive=$archiveName;sha256=$expectedArchives[$archiveName]};provenance=[ordered]@{kind='exact-preserved-stage';receipt_sha256=Get-ObserverSha $stageReceiptPath};immutable=$true})
}
$lease=New-MIRImmutableInputLease -RunRoot $leaseRoot -StageDirectory $mods -Inputs $inputs -RequireHardLinks
Add-MIRNativeProbeImmutableLease -Context $resources -Lease $lease
Publish-MIRModDirectoryArchive -Source $fixture -Name 'mir-fixture-assert-f210-current-bob-angel-final-routes-observer' -Version '0.1.0' -ModsDir $mods|Out-Null
@{mods=@($modNames|ForEach-Object{[ordered]@{name=$_;enabled=$true}})}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $mods 'mod-list.json') -Encoding utf8
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent)-Parent)-Parent
[IO.File]::WriteAllText((Join-Path $run 'config.ini'),"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($userdata.Replace('\','/'))`n",[Text.UTF8Encoding]::new($false))
$engineRun=Invoke-MIRNativeProbeProcess -Context $resources -FilePath $engine -TimeoutSeconds 180 -Arguments @('--config',(Join-Path $run 'config.ini'),'--no-log-rotation','--disable-audio','--mod-directory',$mods,'--create',(Join-Path $run 'observer.zip'))
$factorioLog=Join-Path $userdata 'factorio-current.log'
}
Assert-Observer (Test-Path -LiteralPath $factorioLog -PathType Leaf) 'Factorio log absent.'
Assert-Observer ((Get-Item -LiteralPath $factorioLog).Length -le 32MB) 'Factorio log exceeds the observation budget.'
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
$visibleReturns=@([regex]::Matches($logText,'\[mir-f210-current-ba-final-observer\] VISIBLE_RETURN recipe=(?<recipe>[^\s]+) status=(?<status>reachable|absent) target=(?<target>[^\s]+) steps=(?<steps>[0-9]+) path=(?<path>[^\r\n]+)')|ForEach-Object{[ordered]@{recipe=$_.Groups['recipe'].Value;status=$_.Groups['status'].Value;target=$_.Groups['target'].Value;steps=[int]$_.Groups['steps'].Value;path=$_.Groups['path'].Value}})
Assert-Observer ($visibleReturns.Count -eq 22) "expected 22 visible return records; got $($visibleReturns.Count)."
foreach($record in $visibleReturns){Assert-Observer (@($routes|Where-Object{$_.recipe -ceq $record.recipe}).Count -eq 1) "visible return route is outside candidate list: $($record.recipe)";Assert-Observer (($record.status -ceq 'absent' -and $record.target -ceq '-' -and $record.steps -eq 0) -or ($record.status -ceq 'reachable' -and $record.target -cne '-' -and $record.steps -gt 0)) "visible return record is inconsistent: $($record.recipe)"}
$scienceIngredients=@([regex]::Matches($logText,'\[mir-f210-current-ba-final-observer\] SCIENCE_INGREDIENT item=(?<item>[^\s]+) prototype=(?<prototype>[^\s]+) hidden=(?<hidden>[^\s]+) producers=(?<producers>[^\s]+) producer_count=(?<count>[0-9]+)')|ForEach-Object{[ordered]@{item=$_.Groups['item'].Value;prototype=$_.Groups['prototype'].Value;hidden=$_.Groups['hidden'].Value;producers=$_.Groups['producers'].Value;producer_count=[int]$_.Groups['count'].Value}})
Assert-Observer ($scienceIngredients.Count -eq 3 -and @($scienceIngredients|Where-Object{$_.item -ceq 'bob-sodium-hydroxide'}).Count -eq 1 -and @($scienceIngredients|Where-Object{$_.item -ceq 'angels-solid-sodium-hydroxide'}).Count -eq 1 -and @($scienceIngredients|Where-Object{$_.item -ceq 'bob-salt'}).Count -eq 1) 'chemical-science ingredient producer observations are incomplete.'
$scienceProducers=@([regex]::Matches($logText,'\[mir-f210-current-ba-final-observer\] SCIENCE_PRODUCER item=(?<item>[^\s]+) recipe=(?<recipe>[^\s]+) source=(?<source>[^\s]+) hidden=(?<hidden>[^\s]+) enabled_without_research=(?<enabled>[^\s]+)')|ForEach-Object{[ordered]@{item=$_.Groups['item'].Value;recipe=$_.Groups['recipe'].Value;source=$_.Groups['source'].Value;hidden=$_.Groups['hidden'].Value;enabled_without_research=$_.Groups['enabled'].Value}})
$normalScience=@([regex]::Matches($logText,'\[mir-f210-current-ba-final-observer\] NORMAL_SCIENCE pack=(?<pack>[^\s]+) status=(?<status>[^\s]+) prerequisite=(?<prerequisite>[^\s]+)')|ForEach-Object{[ordered]@{pack=$_.Groups['pack'].Value;status=$_.Groups['status'].Value;prerequisite=$_.Groups['prerequisite'].Value}})
Assert-Observer ($normalScience.Count -eq 2 -and @($normalScience|Where-Object{$_.pack -ceq 'logistic-science-pack'}).Count -eq 1 -and @($normalScience|Where-Object{$_.pack -ceq 'chemical-science-pack'}).Count -eq 1) 'ordinary science production observations are incomplete.'
$normalRejections=@([regex]::Matches($logText,'\[mir-f210-current-ba-final-observer\] NORMAL_REJECTION technology=(?<technology>[^\s]+) recipe=(?<recipe>[^\s]+) reason=(?<reason>[^\s]+)')|ForEach-Object{[ordered]@{technology=$_.Groups['technology'].Value;recipe=$_.Groups['recipe'].Value;reason=$_.Groups['reason'].Value}})
$normalCompletion=[regex]::Match($logText,'\[mir-f210-current-ba-final-observer\] NORMAL_OBSERVATION PASS parent_state_unchanged=true retained_rejections=(?<count>[0-9]+)')
Assert-Observer ($normalCompletion.Success -and $normalRejections.Count -le 64 -and $normalRejections.Count -eq [int]$normalCompletion.Groups['count'].Value) 'ordinary science observation did not preserve parent state or rejection bounds.'
$prepared['material_outcomes']=Get-ObserverMaterialOutcomeInventory $logText
$result=[ordered]@{};foreach($key in $prepared.Keys){$result[$key]=$prepared[$key]};$result.status='observed';$result.engine=[ordered]@{version=([regex]::Match($version,'Version:\s+[^\r\n]+').Value).Trim();executable_sha256=Get-ObserverSha $engine};$result.run_root=$run;$result.recovered_from_completed_engine_run=[bool]$RecoverRunRoot;$result.route_records=$routes;$result.visible_return_records=$visibleReturns;$result.science_ingredient_records=$scienceIngredients;$result.science_producer_records=$scienceProducers;$result.normal_science_records=$normalScience;$result.normal_science_rejections=$normalRejections;$result.normal_observation_parent_state_unchanged=$true;$result.gold_return_path=[ordered]@{target='angels-liquid-molten-gold';start='item:bob-gold-plate';edge_count=$goldEdges.Count;edges=$goldEdges};$result.summary=[ordered]@{observed=[int]$summary.Groups['observed'].Value;missing=[int]$summary.Groups['missing'].Value;science_frontier_packs=[int]$frontier.Groups['packs'].Value;science_frontier_early_present=[int]$frontier.Groups['early'].Value;visible_return_reachable=@($visibleReturns|Where-Object{$_.status -ceq 'reachable'}).Count};$result.native_engine_executed_this_invocation=(-not [bool]$RecoverRunRoot)
if(-not $RecoverRunRoot){
  $result.logs=[ordered]@{stdout=Get-ObserverArtifact $engineRun.stdout;stderr=Get-ObserverArtifact $engineRun.stderr;factorio=Get-ObserverArtifact $factorioLog}
  $result.resource_runs=$resources.runs.ToArray()
  $result.save=Get-ObserverArtifact (Join-Path $run 'observer.zip')
  $result.input_lease=Complete-MIRImmutableInputLease -Lease $lease -Outcome passed
  $lease=$null
  Write-MIRNativeProbeResult -Context $resources -Record $result
}
$result|ConvertTo-Json -Depth 30
Write-Output "Evidence: $run"
}catch{
  $failure=$_
  if($null -ne $resources -and (Test-Path -LiteralPath $resources.root)){
    try{Write-MIRNativeProbeResult -Context $resources -Record ([ordered]@{status='failed';scope='Final Bob/Angel observation; no route admission';source=$source;error=$failure.Exception.Message;resource_runs=$resources.runs.ToArray()})}catch{Write-Warning "Failed observation result exceeded its output budget; owned ledgers remain in $($resources.root)."}
  }
  throw $failure
}finally{
  if($null -ne $lease -and -not $lease.closed){$null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed}
}
