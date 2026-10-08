# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='D:\Programs\Factorio\2.0\bin\x64\factorio.exe',
  [string]$CandidateZip='',
  [string]$SourceMaterializationPath='',
  [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB=0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120,
  [string]$OutputRoot='build/p/m421-f200-cap'
)

$ErrorActionPreference='Stop'
$inputLeases=@()
# Native execution is retired; the preserved oracle is not current acceptance.
throw '[mir-native-obsolete-runner] This native runner still materializes a mod directory. Use a migrated direct-library consumer; retain this scenario and its historical evidence until conversion. No engine or staging was started.'
Set-StrictMode -Version Latest

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$buildRoot=[IO.Path]::GetFullPath((Join-Path $repo 'build'))+[IO.Path]::DirectorySeparatorChar
if(-not$output.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'F200 settings-cap-transition evidence output must be under build.'}
$engineSha='D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B'
$fixtureName='mir-fixture-assert-mir42-f200-settings-cap-transition'
$nonClaims=@('F210','F200-V2-to-V3-transported-ownership-migration','same-value-foreign-write-detection','external-queue-manager-interoperability-or-queue-ownership','CAP-FOREIGN-DISABLE','multiplayer-gameplay-or-human-playtest','all-stream-or-ecosystem-coverage','release-readiness-or-publication-authorization')
$officialExpansionMods=@('elevated-rails','quality','space-age')
$expectedEnabledModNames=@('base','more-infinite-research',$fixtureName,'mir-validation-settings-overrides')
$expectedEngineLoadedModNames=@('core')+$expectedEnabledModNames|Sort-Object

function Assert-MIR42F200([bool]$Condition,[string]$Message){if(-not$Condition){throw "[mir42-f200-settings-cap-transition] $Message"}}
function Assert-Exact([string]$Name,$Actual,$Expected){if($null-eq$Actual-and$null-eq$Expected){return};if($null-eq$Actual-or$null-eq$Expected-or$Actual-cne$Expected){throw "[mir42-f200-settings-cap-transition] $Name differs: expected '$Expected', actual '$Actual'."}}
function Get-Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Get-Artifact([string]$Path){$resolved=(Resolve-Path -LiteralPath $Path).Path;Assert-MIR42F200 $resolved.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) "artifact escapes repository: $resolved";[ordered]@{path=$resolved.Substring($repo.Length+1).Replace('\','/');bytes=(Get-Item -LiteralPath $resolved).Length;sha256=Get-Sha $resolved}}
function Assert-Properties([string]$Name,$Value,[string[]]$Expected){Assert-MIR42F200 ($null-ne$Value) "$Name is absent.";$actual=@($Value.PSObject.Properties.Name|Sort-Object);$wanted=@($Expected|Sort-Object);Assert-Exact "$Name properties" ($actual-join"`n") ($wanted-join"`n")}
function Read-State([string]$Text,[string]$Stage){$matches=@([regex]::Matches($Text,'\[mir42-f200-settings-cap-transition\] STATE JSON (?<json>\{[^\r\n]+\})')|ForEach-Object{try{$value=$_.Groups['json'].Value|ConvertFrom-Json -ErrorAction Stop}catch{throw "invalid state JSON: $($_.Exception.Message)"};if([string]$value.stage-ceq$Stage){$value}});Assert-MIR42F200 ($matches.Count-eq1) "expected exactly one $Stage receipt, observed $($matches.Count).";$matches[0]}
function Assert-State($State,[string]$Stage,[int]$Cap,[int]$Changes,[bool]$OwnedEnabled,[bool]$ForeignEnabled,[bool]$VisibleWhenDisabled){Assert-Properties "state.$Stage" $State @('stage','cap','configuration_changed_events','owned','foreign_disabled');Assert-Exact "$Stage.stage" $State.stage $Stage;Assert-Exact "$Stage.cap" ([int]$State.cap) $Cap;Assert-Exact "$Stage.configuration_changed_events" ([int]$State.configuration_changed_events) $Changes;foreach($row in @(@{name='owned';value=$State.owned;enabled=$OwnedEnabled},@{name='foreign_disabled';value=$State.foreign_disabled;enabled=$ForeignEnabled})){Assert-Properties "$Stage.$($row.name)" $row.value @('level','enabled','visible_when_disabled');Assert-Exact "$Stage.$($row.name).level" ([int]$row.value.level) 4;Assert-Exact "$Stage.$($row.name).enabled" ([bool]$row.value.enabled) ([bool]$row.enabled);Assert-Exact "$Stage.$($row.name).visible_when_disabled" ([bool]$row.value.visible_when_disabled) $VisibleWhenDisabled}}
function New-MIR42F200BaseOnlyModList {
  $mods=@()
  foreach($name in $expectedEnabledModNames){$mods += [ordered]@{name=[string]$name;enabled=$true}}
  foreach($name in $officialExpansionMods){$mods += [ordered]@{name=[string]$name;enabled=$false}}
  [ordered]@{mods=$mods}
}
function Assert-MIR42F200BaseOnlyStageModList($Stage){
  $modList=Get-Content -Raw -LiteralPath $Stage.mod_list|ConvertFrom-Json -Depth 8
  Assert-Properties "stage.$($Stage.name).mod_list" $modList @('mods')
  $rows=@($modList.mods);$expectedNames=@($expectedEnabledModNames+$officialExpansionMods|Sort-Object)
  Assert-Exact "stage.$($Stage.name).mod_list.names" ((@($rows.name|Sort-Object)-join"`n")) ($expectedNames-join"`n")
  Assert-MIR42F200 (@($rows.name|Sort-Object -Unique).Count-eq$rows.Count) "stage $($Stage.name) mod-list contains duplicate names."
  foreach($name in $expectedEnabledModNames+$officialExpansionMods){$row=@($rows|Where-Object{[string]$_.name-ceq$name});Assert-MIR42F200 ($row.Count-eq1) "stage $($Stage.name) mod-list has no unique $name entry.";Assert-Properties "stage.$($Stage.name).mod_list.$name" $row[0] @('name','enabled');Assert-Exact "stage.$($Stage.name).mod_list.$name.enabled" ([bool]$row[0].enabled) ([bool]($name-notin$officialExpansionMods))}
  [ordered]@{stage=$Stage.name;declared_mods=@($rows|Sort-Object name|ForEach-Object{[ordered]@{name=[string]$_.name;enabled=[bool]$_.enabled}})}
}
function Get-MIR42F200EffectiveEngineLoadedClosure([string]$Text,[string]$Stage){
  $dataRows=@([regex]::Matches($Text,'(?m)^.*?Loading mod (?!settings )(?<name>[^\s]+) (?<version>[^\s]+) \((?<phase>[^)]+)\)\s*$')|ForEach-Object{[pscustomobject][ordered]@{name=$_.Groups['name'].Value;version=$_.Groups['version'].Value;phase=$_.Groups['phase'].Value}})
  $settingsRows=@([regex]::Matches($Text,'(?m)^.*?Loading mod settings (?<name>[^\s]+) (?<version>[^\s]+) \((?<phase>[^)]+)\)\s*$')|ForEach-Object{[pscustomobject][ordered]@{name=$_.Groups['name'].Value;version=$_.Groups['version'].Value;phase=$_.Groups['phase'].Value}})
  $rows=@($dataRows+$settingsRows)
  Assert-MIR42F200 ($rows.Count-gt0) "stage $Stage has no Factorio mod-load records."
  $mods=@(foreach($name in @($rows.name|Sort-Object -Unique)){$matching=@($rows|Where-Object{[string]$_.name-ceq$name});$versions=@($matching.version|Sort-Object -Unique);Assert-MIR42F200 ($versions.Count-eq1) "stage $Stage loaded $name with multiple versions.";[ordered]@{name=$name;version=$versions[0];phases=@($matching.phase|Sort-Object -Unique)}})
  Assert-Exact "stage.$Stage.engine_loaded_mod_names" ((@($mods.name|Sort-Object)-join"`n")) ($expectedEngineLoadedModNames-join"`n")
  foreach($name in $officialExpansionMods){Assert-MIR42F200 ($name-notin@($mods.name)) "stage $Stage loaded disabled official expansion $name."}
  [ordered]@{stage=$Stage;loaded_mods=$mods}
}

$running=@(Get-Process -Name factorio -ErrorAction SilentlyContinue)
Assert-MIR42F200 ($running.Count-eq0) 'requires the one-Factorio-process policy; a Factorio process is already running.'
$sourceCommit=(& git -C $repo rev-parse HEAD).Trim();$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
Assert-MIR42F200 ($sourceCommit-match'^[0-9a-f]{40}$'-and$sourceTree-match'^[0-9a-f]{40}$') 'requires source commit/tree identities.'
$candidateClosure=@('source','targets','tools/mir/application/package','tools/lib/validation/PackageIdentity.ps1','spec/schemas/mir4-canonical-package-authority-v2.schema.json','spec/schemas/mir4-package-composition-result-v1.schema.json')
$candidateChanges=@(& git -C $repo status --porcelain --untracked-files=all -- $candidateClosure)
Assert-MIR42F200 ($candidateChanges.Count-eq0) "requires clean candidate-materialization inputs: $($candidateChanges-join'; ')"

. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/validation/SettingsOverrides.ps1')
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
$resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $output -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
$candidateInput=Read-MIRNativeProbeCurrentCandidate -Repository $repo -Archive $CandidateZip -ReceiptPath $SourceMaterializationPath -Target f200
$candidateZip=[string]$candidateInput.path
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
Assert-Exact 'Factorio executable SHA-256' (Get-Sha $engine) $engineSha
$inputLeases=[Collections.Generic.List[object]]::new()
trap {
  $failure=$_
  foreach($inputLease in $inputLeases){
    if(-not $inputLease.closed){
      try { $null=Complete-MIRImmutableInputLease -Lease $inputLease -Outcome failed } catch {}
    }
  }
  throw $failure
}
New-Item -ItemType Directory -Path $resources.root | Out-Null
$versionActor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments @('--version') -TimeoutSeconds 30
$engineVersion=Get-Content -LiteralPath $versionActor.stdout -Raw
Assert-MIR42F200 ($engineVersion-match'Version: 2[.]0[.]77') 'requires exact Factorio 2.0.77.'
$engineVersion=([regex]::Match($engineVersion,'Version:\s+2[.]0[.]77[^\r\n]*').Value).Trim()
$fixture=Join-Path $repo 'fixtures/assert-mir42-f200-settings-cap-transition'
Assert-MIR42F200 (Test-Path -LiteralPath $fixture -PathType Container) 'fixture is absent.'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($candidateZip)
try{
  $forbidden=@($archive.Entries|Where-Object{$_.FullName-match'(^|/)(fixtures|tests|docs|[.]mir|build|dist)(/|$)'})
  if($forbidden.Count-ne0){throw "[mir42-f200-settings-cap-transition] candidate has package-excluded path $($forbidden[0].FullName)"}
}finally{$archive.Dispose()}

$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent)-Parent)-Parent
function New-Stage([string]$Name,[int]$Cap){
  $root=Join-Path $resources.root $Name;$mods=Join-Path $root 'mods';$userdata=Join-Path $root 'userdata'
  New-Item -ItemType Directory -Force -Path $mods,$userdata,(Join-Path $userdata 'saves')|Out-Null
  $input=[ordered]@{source_path=$candidateZip;file_name=[IO.Path]::GetFileName($candidateZip);expected_sha256=[string]$candidateInput.receipt.archive_sha256;role='candidate';identity=@{target='f200';version='4.2.20001'};provenance=@{kind='verified-current-canonical-materialization';package_source_sha256=[string]$candidateInput.receipt.package_source_sha256};immutable=$true}
  $lease=New-MIRImmutableInputLease -RunRoot $root -StageDirectory $mods -Inputs @($input) -RequireHardLinks
  $inputLeases.Add($lease)
  Add-MIRNativeProbeImmutableLease -Context $resources -Lease $lease
  $fixtureArchive=Publish-MIRModDirectoryArchive -Source $fixture -Name $fixtureName -Version '0.1.0' -ModsDir $mods
  Initialize-MIRSettingsOverrideMod -ModsDir $mods -FactorioVersion '2.0'
  Set-CopiedStartupSettingDefaults -ModsDir $mods -Overrides @{'ips-enable-research_copper'=$true;'ips-max-level-research_copper'=$Cap}
  Complete-MIRSettingsOverrideMod -ModsDir $mods
  $modList=New-MIR42F200BaseOnlyModList
  $modListPath=Join-Path $mods 'mod-list.json';[IO.File]::WriteAllText($modListPath,(($modList|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  $config=Join-Path $root 'config.ini';[IO.File]::WriteAllText($config,"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($userdata.Replace('\','/'))`n",[Text.UTF8Encoding]::new($false))
  $server=Join-Path $root 'server-settings.json';$serverData=[ordered]@{name='MIR42 F200 settings-derived cap transition';description='';tags=@();max_players=1;visibility=[ordered]@{public=$false;lan=$false};require_user_verification=$false;auto_pause=$false};[IO.File]::WriteAllText($server,(($serverData|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  [pscustomobject]@{name=$Name;cap=$Cap;root=$root;mods=$mods;userdata=$userdata;config=$config;server=$server;fixture_archive=$fixtureArchive;settings_archive=(Join-Path $mods 'mir-validation-settings-overrides_0.1.0.zip');mod_list=$modListPath;lease=$lease}
}
function Invoke-Engine($Stage,[string]$Name,[string[]]$Arguments){
  $factorioLog=Join-Path $Stage.userdata 'factorio-current.log';if(Test-Path -LiteralPath $factorioLog){Remove-Item -LiteralPath $factorioLog -Force}
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments (@('--config',$Stage.config,'--no-log-rotation','--disable-audio','--mod-directory',$Stage.mods)+$Arguments) -TimeoutSeconds 120
  Assert-MIR42F200 (Test-Path -LiteralPath $factorioLog -PathType Leaf) "Factorio log is absent after $Name.";$copy=Join-Path $Stage.root "factorio-$Name.log";Copy-Item -LiteralPath $factorioLog -Destination $copy;$copy
}
function Invoke-ServerSave($Stage,[string]$Name,[string]$InputSave,[string]$ExpectedSave,[string]$ExpectedStage){
  $factorioLog=Join-Path $Stage.userdata 'factorio-current.log';if(Test-Path -LiteralPath $factorioLog){Remove-Item -LiteralPath $factorioLog -Force}
  $needle="[mir42-f200-settings-cap-transition] STATE JSON {`"stage`":`"$ExpectedStage`""
  $completion={
    if(-not(Test-Path -LiteralPath $factorioLog -PathType Leaf)-or -not(Test-Path -LiteralPath $ExpectedSave -PathType Leaf)){return $false}
    try { $text=Get-Content -LiteralPath $factorioLog -Raw -ErrorAction Stop } catch [IO.IOException] { return $false }
    return ($null -ne $text -and $text.Contains($needle)-and$text.Contains('Saving finished'))
  }.GetNewClosure()
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments @('--config',$Stage.config,'--no-log-rotation','--disable-audio','--mod-directory',$Stage.mods,'--server-settings',$Stage.server,'--start-server',$InputSave) -TimeoutSeconds 60 -CompletionPredicate $completion
  Assert-MIR42F200 ([bool]$actor.result.completion_predicate_observed) "Factorio server did not create $Name successor."
  Assert-MIR42F200 (Test-Path -LiteralPath $factorioLog -PathType Leaf) "Factorio log is absent after $Name.";$copy=Join-Path $Stage.root "factorio-$Name.log";Copy-Item -LiteralPath $factorioLog -Destination $copy;$copy
}

$seed=New-Stage seed 0;$capped=New-Stage capped 3;$relaxed=New-Stage relaxed 0
$stages=@($seed,$capped,$relaxed);$stageModListContracts=[ordered]@{};foreach($stage in $stages){$stageModListContracts[[string]$stage.name]=Assert-MIR42F200BaseOnlyStageModList $stage}
$seedSave=Join-Path $seed.root 'seed.zip';$seedLog=Invoke-Engine $seed seed @('--create',$seedSave);Assert-MIR42F200 (Test-Path -LiteralPath $seedSave -PathType Leaf) 'seed save is absent.'
$cappedSave=Join-Path $capped.userdata 'saves/mir42-f200-settings-cap-transition-capped.zip';$cappedLog=Invoke-ServerSave $capped capped $seedSave $cappedSave capped
$relaxedSave=Join-Path $relaxed.userdata 'saves/mir42-f200-settings-cap-transition-relaxed.zip';$relaxedLog=Invoke-ServerSave $relaxed relaxed $cappedSave $relaxedSave relaxed
$seedText=Get-Content -Raw -LiteralPath $seedLog;$cappedText=Get-Content -Raw -LiteralPath $cappedLog;$relaxedText=Get-Content -Raw -LiteralPath $relaxedLog
Assert-MIR42F200 ([regex]::Matches($seedText,'\[mir42-f200-settings-cap-transition\] DATA policy-transport=settings-derived-v3 mod-data=absent').Count-eq1) 'F200 data-stage fallback receipt is absent.'
$effectiveEngineLoadedClosure=[ordered]@{expected_mod_names=$expectedEngineLoadedModNames;stages=[ordered]@{seed=Get-MIR42F200EffectiveEngineLoadedClosure $seedText seed;capped=Get-MIR42F200EffectiveEngineLoadedClosure $cappedText capped;relaxed=Get-MIR42F200EffectiveEngineLoadedClosure $relaxedText relaxed}}
$seedState=Read-State $seedText seed;$cappedState=Read-State $cappedText capped;$relaxedState=Read-State $relaxedText relaxed
Assert-State $seedState seed 0 0 $true $false $false;Assert-State $cappedState capped 3 1 $false $false $true;Assert-State $relaxedState relaxed 0 2 $true $false $false
Assert-MIR42F200 (Test-Path -LiteralPath $cappedSave -PathType Leaf) 'capped save is absent.';Assert-MIR42F200 (Test-Path -LiteralPath $relaxedSave -PathType Leaf) 'relaxed save is absent.'
$lineage=@([ordered]@{stage='seed';save=Get-Artifact $seedSave;predecessor_sha256=$null},[ordered]@{stage='capped';save=Get-Artifact $cappedSave;predecessor_sha256=Get-Sha $seedSave},[ordered]@{stage='relaxed';save=Get-Artifact $relaxedSave;predecessor_sha256=Get-Sha $cappedSave})
$result=[ordered]@{schema=1;kind='MIR42F200SettingsDerivedMaximumLevelCapTransitionQualificationV1';status='passed-current-f200-settings-derived-cap-transition-only';scope='Verified supplied 4.2.20001 F200 candidate with no mod-data policy transport: settings-derived V3 cap ownership disables/restores only MIR-owned enablement and visibility across finite cap three to cap zero; isolated/cooperative force ownership evidence.';target=[ordered]@{factorio_line='2.0';factorio_version='2.0.77';engine_sha256=$engineSha};declared_base_only_mod_closure=[ordered]@{enabled_mod_names=$expectedEnabledModNames;explicitly_disabled_official_expansions=$officialExpansionMods};effective_engine_loaded_closure=$effectiveEngineLoadedClosure;source=[ordered]@{commit=$sourceCommit;tree=$sourceTree;package_source_sha256=[string]$candidateInput.receipt.package_source_sha256;package_source_manifest_sha256=Get-Sha (Join-Path $repo 'source/package-source.json');candidate_materialization_inputs=$candidateClosure;candidate_materialization_inputs_clean=$true};candidate=Get-Artifact $candidateZip;fixture_hashes=[ordered]@{info=Get-Sha (Join-Path $fixture 'info.json');data_final_fixes=Get-Sha (Join-Path $fixture 'data-final-fixes.lua');control=Get-Sha (Join-Path $fixture 'control.lua')};harness_sha256=Get-Sha $PSCommandPath;stages=@($stages|ForEach-Object{[ordered]@{name=$_.name;cap=$_.cap;fixture=Get-Artifact $_.fixture_archive;settings=Get-Artifact $_.settings_archive;mod_list=Get-Artifact $_.mod_list;mod_list_contract=$stageModListContracts[[string]$_.name]}});state_receipts=[ordered]@{seed=$seedState;capped=$cappedState;relaxed=$relaxedState};save_lineage=$lineage;logs=[ordered]@{seed=Get-Artifact $seedLog;capped=Get-Artifact $cappedLog;relaxed=Get-Artifact $relaxedLog};explicit_non_claims=$nonClaims}
$result['candidate_materialization']=Get-Artifact $SourceMaterializationPath
$result['candidate_created_by_harness']=$false
$result['input_staging']=@($stages|ForEach-Object { Complete-MIRImmutableInputLease -Lease $_.lease -Outcome passed })
$result['resource_context']=[ordered]@{expected_peak_memory_bytes=$resources.peak_memory_bytes;max_new_output_bytes=$resources.max_new_output_bytes;shared_alias_bytes=$resources.shared_alias_bytes;memory_enforcement='sampled-watchdog-not-hard-cap'}
$result['process_inventory']=@($resources.runs)
Write-MIRNativeProbeResult -Context $resources -Record $result
$result|ConvertTo-Json -Depth 40;Write-Output "Evidence: $($resources.root)"
