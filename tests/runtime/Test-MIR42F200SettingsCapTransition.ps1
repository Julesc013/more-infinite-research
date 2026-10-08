# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='',
  [string]$LibraryDirectory='',
  [switch]$PrepareInputsOnly,
  [string]$CandidateZip='',
  [string]$SourceMaterializationPath='',
  [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB=0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120,
  [string]$OutputRoot='build/p/m421-f200-cap'
)

$ErrorActionPreference='Stop'
$resources=$null;$activeStage=$null
Set-StrictMode -Version Latest
if(-not $PrepareInputsOnly -and (-not $FactorioBin -or -not $LibraryDirectory)){
  throw '[mir42-f200-direct-inputs-required] Supply an explicit engine and flat archive library. No populated profile is created.'
}

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
function Get-Artifact([string]$Path,[switch]$AllowExternal){$resolved=(Resolve-Path -LiteralPath $Path).Path;Assert-MIRLibraryPath $resolved;$inside=$resolved.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase);Assert-MIR42F200 ($inside-or$AllowExternal) "artifact escapes repository: $resolved";[ordered]@{path=$(if($inside){$resolved.Substring($repo.Length+1).Replace('\','/')}else{$resolved});path_kind=$(if($inside){'repository-relative'}else{'machine-local-input'});bytes=(Get-Item -LiteralPath $resolved).Length;sha256=Get-Sha $resolved}}
function Assert-Properties([string]$Name,$Value,[string[]]$Expected){Assert-MIR42F200 ($null-ne$Value) "$Name is absent.";$actual=@($Value.PSObject.Properties.Name|Sort-Object);$wanted=@($Expected|Sort-Object);Assert-Exact "$Name properties" ($actual-join"`n") ($wanted-join"`n")}
function Read-State([string]$Text,[string]$Stage){$matches=@([regex]::Matches($Text,'\[mir42-f200-settings-cap-transition\] STATE JSON (?<json>\{[^\r\n]+\})')|ForEach-Object{try{$value=$_.Groups['json'].Value|ConvertFrom-Json -ErrorAction Stop}catch{throw "invalid state JSON: $($_.Exception.Message)"};if([string]$value.stage-ceq$Stage){$value}});Assert-MIR42F200 ($matches.Count-eq1) "expected exactly one $Stage receipt, observed $($matches.Count).";$matches[0]}
function Assert-State($State,[string]$Stage,[int]$Cap,[int]$Changes,[bool]$OwnedEnabled,[bool]$ForeignEnabled,[bool]$VisibleWhenDisabled){Assert-Properties "state.$Stage" $State @('stage','cap','configuration_changed_events','owned','foreign_disabled');Assert-Exact "$Stage.stage" $State.stage $Stage;Assert-Exact "$Stage.cap" ([int]$State.cap) $Cap;Assert-Exact "$Stage.configuration_changed_events" ([int]$State.configuration_changed_events) $Changes;foreach($row in @(@{name='owned';value=$State.owned;enabled=$OwnedEnabled},@{name='foreign_disabled';value=$State.foreign_disabled;enabled=$ForeignEnabled})){Assert-Properties "$Stage.$($row.name)" $row.value @('level','enabled','visible_when_disabled');Assert-Exact "$Stage.$($row.name).level" ([int]$row.value.level) 4;Assert-Exact "$Stage.$($row.name).enabled" ([bool]$row.value.enabled) ([bool]$row.enabled);Assert-Exact "$Stage.$($row.name).visible_when_disabled" ([bool]$row.value.visible_when_disabled) $VisibleWhenDisabled}}
function New-MIR42F200BaseOnlyModList([string]$SettingsVersion) {
  $versions=@{base='2.0.77';'more-infinite-research'='4.2.20001';$fixtureName='0.1.0';'mir-validation-settings-overrides'=$SettingsVersion}
  $mods=@()
  foreach($name in $expectedEnabledModNames){$mods += [ordered]@{name=[string]$name;version=[string]$versions[$name];enabled=$true}}
  foreach($name in $officialExpansionMods){$mods += [ordered]@{name=[string]$name;enabled=$false}}
  [ordered]@{mods=$mods}
}
function Assert-MIR42F200BaseOnlyStageModList($Stage){
  $modList=Get-Content -Raw -LiteralPath $Stage.mod_list|ConvertFrom-Json -Depth 8
  Assert-Properties "stage.$($Stage.name).mod_list" $modList @('mods')
  $rows=@($modList.mods);$expectedNames=@($expectedEnabledModNames+$officialExpansionMods|Sort-Object)
  Assert-Exact "stage.$($Stage.name).mod_list.names" ((@($rows.name|Sort-Object)-join"`n")) ($expectedNames-join"`n")
  Assert-MIR42F200 (@($rows.name|Sort-Object -Unique).Count-eq$rows.Count) "stage $($Stage.name) mod-list contains duplicate names."
  foreach($name in $expectedEnabledModNames+$officialExpansionMods){$row=@($rows|Where-Object{[string]$_.name-ceq$name});Assert-MIR42F200 ($row.Count-eq1) "stage $($Stage.name) mod-list has no unique $name entry.";$fields=if($name-in$officialExpansionMods){@('name','enabled')}else{@('name','version','enabled')};Assert-Properties "stage.$($Stage.name).mod_list.$name" $row[0] $fields;Assert-Exact "stage.$($Stage.name).mod_list.$name.enabled" ([bool]$row[0].enabled) ([bool]($name-notin$officialExpansionMods))}
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
. (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 3 -MaxEntriesPerRoot 400 -MaxWorktrees 8 -MaxBranches 32 | Out-Host
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
$resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $output -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
$candidateInput=Read-MIRNativeProbeCurrentCandidate -Repository $repo -Archive $CandidateZip -ReceiptPath $SourceMaterializationPath -Target f200
$candidateZip=[string]$candidateInput.path
$activeStage=$null
trap {
  $failure=$_
  if($null-ne$activeStage-and$null-ne$activeStage.activation-and-not$activeStage.activation.closed){
    try{$activeStage.terminal=Complete-MIRLibraryActivation $activeStage.activation}catch{Write-Warning $_.Exception.Message}
  }
  if($null-ne$resources-and(Test-Path -LiteralPath $resources.root)){
    try{Write-MIRNativeProbeResult -Context $resources -Record @{status='failed';error=$failure.Exception.Message;source=$sourceCommit;resource_runs=$resources.runs.ToArray()}}catch{Write-Warning $_.Exception.Message}
  }
  throw $failure
}
New-Item -ItemType Directory -Path $resources.root | Out-Null
$fixture=Join-Path $repo 'fixtures/assert-mir42-f200-settings-cap-transition'
Assert-MIR42F200 (Test-Path -LiteralPath $fixture -PathType Container) 'fixture is absent.'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($candidateZip)
try{
  $forbidden=@($archive.Entries|Where-Object{$_.FullName-match'(^|/)(fixtures|tests|docs|[.]mir|build|dist)(/|$)'})
  if($forbidden.Count-ne0){throw "[mir42-f200-settings-cap-transition] candidate has package-excluded path $($forbidden[0].FullName)"}
}finally{$archive.Dispose()}

# These are two small MIR-owned settings fixtures, retained once in the
# selected library. They are distinct exact versions, not alternate MIR builds.
function New-CapSettingsSource([string]$Root,[int]$Cap){
  Assert-MIR42F200 ($Cap-in@(0,3)) 'unsupported cap fixture'
  Initialize-MIRSettingsOverrideMod -ModsDir $Root -FactorioVersion '2.0'
  Set-CopiedStartupSettingDefaults -ModsDir $Root -Overrides @{'ips-enable-research_copper'=$true;'ips-max-level-research_copper'=$Cap}
  $source=Join-Path $Root 'mir-validation-settings-overrides'
  $infoPath=Join-Path $source 'info.json';$info=Get-Content -LiteralPath $infoPath -Raw|ConvertFrom-Json
  $info.version=if($Cap-eq0){'0.1.100'}else{'0.1.103'}
  [IO.File]::WriteAllText($infoPath,($info|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  [pscustomobject]@{source=$source;version=$info.version;file=('mir-validation-settings-overrides_'+$info.version+'.zip')}
}
$preparedSettings=@{}
foreach($cap in @(0,3)){$preparedSettings[$cap]=New-CapSettingsSource (Join-Path $resources.root ('input-definitions/cap-'+$cap)) $cap}
if($PrepareInputsOnly){
  $assets=Join-Path $resources.root 'owned-inputs';[IO.Directory]::CreateDirectory($assets)|Out-Null
  $archives=@(Publish-MIRModDirectoryArchive -Source $fixture -Name $fixtureName -Version '0.1.0' -ModsDir $assets)
  foreach($cap in @(0,3)){$input=$preparedSettings[$cap];$archives+=Publish-MIRModDirectoryArchive -Source $input.source -Name 'mir-validation-settings-overrides' -Version $input.version -ModsDir $assets}
  Write-MIRNativeProbeResult -Context $resources -Record @{status='prepared-owned-inputs-only';source=$sourceCommit;candidate=Get-Artifact $candidateZip;archives=@($archives|ForEach-Object{Get-Artifact $_});native_factorio=$false}
  Write-Output "Prepared inputs: $($resources.root)";return
}
Assert-MIR42F200 (-not[string]::IsNullOrWhiteSpace($FactorioBin)-and-not[string]::IsNullOrWhiteSpace($LibraryDirectory)) 'supply an explicit engine and flat archive library'
Assert-MIR441CleanTrackedSource -RepoRoot $repo
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path;Assert-MIRLibraryPath $engine
Assert-Exact 'Factorio executable SHA-256' (Get-Sha $engine) $engineSha
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent)-Parent)-Parent
$library=(Resolve-Path -LiteralPath $LibraryDirectory).Path;Assert-MIRLibraryPath $library
$versionActor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments @('--version') -TimeoutSeconds 30
$engineVersion=Get-Content -LiteralPath $versionActor.stdout -Raw
Assert-MIR42F200 ($engineVersion-match'Version: 2[.]0[.]77') 'requires exact Factorio 2.0.77.'
$engineVersion=([regex]::Match($engineVersion,'Version:\s+2[.]0[.]77[^\r\n]*').Value).Trim()
function New-Stage([string]$Name,[int]$Cap){
  $root=Join-Path $resources.root $Name;$userdata=Join-Path $root 'userdata'
  New-Item -ItemType Directory -Force -Path $userdata,(Join-Path $userdata 'saves')|Out-Null
  $settings=$preparedSettings[$Cap];$settingsArchive=Join-Path $library $settings.file
  $fixtureArchive=Join-Path $library ($fixtureName+'_0.1.0.zip')
  Assert-MIRLibraryFixtureArchive -Archive $fixtureArchive -SourceDirectory $fixture
  Assert-MIRLibraryFixtureArchive -Archive $settingsArchive -SourceDirectory $settings.source
  $candidateName=[IO.Path]::GetFileName($candidateZip);$installed=Join-Path $library $candidateName
  Assert-MIRLibraryPath $installed
  Assert-Exact 'installed candidate hash' (Get-Sha $installed) ([string]$candidateInput.receipt.archive_sha256)
  $hashes=@{$candidateName=[string]$candidateInput.receipt.archive_sha256;([IO.Path]::GetFileName($fixtureArchive))=(Get-Sha $fixtureArchive);$settings.file=(Get-Sha $settingsArchive)}
  $modList=New-MIR42F200BaseOnlyModList $settings.version
  $modListPath=Join-Path $root 'selection.json';[IO.File]::WriteAllText($modListPath,(($modList|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  $config=Join-Path $root 'config.ini';[IO.File]::WriteAllText($config,"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($userdata.Replace('\','/'))`n[other]`nenable-new-mods=false`ncheck-updates=false`ndisable-blueprint-storage=true`n",[Text.UTF8Encoding]::new($false))
  $server=Join-Path $root 'server-settings.json';$serverData=[ordered]@{name='MIR42 F200 settings-derived cap transition';description='';tags=@();max_players=1;visibility=[ordered]@{public=$false;lan=$false};require_user_verification=$false;auto_pause=$false};[IO.File]::WriteAllText($server,(($serverData|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  [pscustomobject]@{name=$Name;cap=$Cap;root=$root;mods=$library;userdata=$userdata;config=$config;server=$server;fixture_archive=$fixtureArchive;settings_archive=$settingsArchive;mod_list=$modListPath;archive_hashes=$hashes;activation=$null;terminal=$null}
}
function Start-CapStage($Stage){
  $Stage.activation=Start-MIRLibraryActivation -LibraryDirectory $Stage.mods -EngineDataDirectory (Join-Path $engineRoot 'data') -ProfilePath $Stage.mod_list -ArchiveHashes $Stage.archive_hashes -SettingsMode Defaults
  $script:activeStage=$Stage
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $Stage.activation
  [IO.File]::WriteAllBytes((Join-Path $Stage.root 'active-mod-list.json'),$Stage.activation.mod_list_bytes)
}
function Complete-CapStage($Stage,[string]$Log){
  $null=Assert-MIRLibraryLoadedSelection -Activation $Stage.activation -LogPath $Log -LatestInvocation
  $Stage.terminal=Complete-MIRLibraryActivation $Stage.activation
  $script:activeStage=$null
}
function Invoke-Engine($Stage,[string]$Name,[string[]]$Arguments){
  Start-CapStage $Stage
  $factorioLog=Join-Path $Stage.userdata 'factorio-current.log';if(Test-Path -LiteralPath $factorioLog){Remove-Item -LiteralPath $factorioLog -Force}
  $nativeArguments=@('--config',$Stage.config,'--no-log-rotation','--disable-audio','--mod-directory',$Stage.mods)+$Arguments
  Assert-MIRLibraryLaunch -Activation $Stage.activation -FactorioBin $engine -Arguments $nativeArguments
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments $nativeArguments -TimeoutSeconds 120
  Assert-MIR42F200 (Test-Path -LiteralPath $factorioLog -PathType Leaf) "Factorio log is absent after $Name.";$copy=Join-Path $Stage.root "factorio-$Name.log";Copy-Item -LiteralPath $factorioLog -Destination $copy;Complete-CapStage $Stage $copy;$copy
}
function Invoke-ServerSave($Stage,[string]$Name,[string]$InputSave,[string]$ExpectedSave,[string]$ExpectedStage){
  Start-CapStage $Stage
  $factorioLog=Join-Path $Stage.userdata 'factorio-current.log';if(Test-Path -LiteralPath $factorioLog){Remove-Item -LiteralPath $factorioLog -Force}
  $needle="[mir42-f200-settings-cap-transition] STATE JSON {`"stage`":`"$ExpectedStage`""
  $completion={
    if(-not(Test-Path -LiteralPath $factorioLog -PathType Leaf)-or -not(Test-Path -LiteralPath $ExpectedSave -PathType Leaf)){return $false}
    try { $text=Get-Content -LiteralPath $factorioLog -Raw -ErrorAction Stop } catch [IO.IOException] { return $false }
    return ($null -ne $text -and $text.Contains($needle)-and$text.Contains('Saving finished'))
  }.GetNewClosure()
  $nativeArguments=@('--config',$Stage.config,'--no-log-rotation','--disable-audio','--mod-directory',$Stage.mods,'--server-settings',$Stage.server,'--start-server',$InputSave)
  Assert-MIRLibraryLaunch -Activation $Stage.activation -FactorioBin $engine -Arguments $nativeArguments
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments $nativeArguments -TimeoutSeconds 60 -CompletionPredicate $completion
  Assert-MIR42F200 ([bool]$actor.result.completion_predicate_observed) "Factorio server did not create $Name successor."
  Assert-MIR42F200 (Test-Path -LiteralPath $factorioLog -PathType Leaf) "Factorio log is absent after $Name.";$copy=Join-Path $Stage.root "factorio-$Name.log";Copy-Item -LiteralPath $factorioLog -Destination $copy;Complete-CapStage $Stage $copy;$copy
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
$result=[ordered]@{schema=1;kind='MIR42F200SettingsDerivedMaximumLevelCapTransitionQualificationV1';status='passed-current-f200-settings-derived-cap-transition-only';scope='Verified supplied 4.2.20001 F200 candidate with no mod-data policy transport: settings-derived V3 cap ownership disables/restores only MIR-owned enablement and visibility across finite cap three to cap zero; isolated/cooperative force ownership evidence.';target=[ordered]@{factorio_line='2.0';factorio_version='2.0.77';engine_sha256=$engineSha};declared_base_only_mod_closure=[ordered]@{enabled_mod_names=$expectedEnabledModNames;explicitly_disabled_official_expansions=$officialExpansionMods};effective_engine_loaded_closure=$effectiveEngineLoadedClosure;source=[ordered]@{commit=$sourceCommit;tree=$sourceTree;package_source_sha256=[string]$candidateInput.receipt.package_source_sha256;package_source_manifest_sha256=Get-Sha (Join-Path $repo 'source/package-source.json');candidate_materialization_inputs=$candidateClosure;candidate_materialization_inputs_clean=$true};candidate=Get-Artifact $candidateZip;fixture_hashes=[ordered]@{info=Get-Sha (Join-Path $fixture 'info.json');data_final_fixes=Get-Sha (Join-Path $fixture 'data-final-fixes.lua');control=Get-Sha (Join-Path $fixture 'control.lua')};harness_sha256=Get-Sha $PSCommandPath;stages=@($stages|ForEach-Object{[ordered]@{name=$_.name;cap=$_.cap;fixture=Get-Artifact $_.fixture_archive -AllowExternal;settings=Get-Artifact $_.settings_archive -AllowExternal;mod_list=Get-Artifact $_.mod_list;mod_list_contract=$stageModListContracts[[string]$_.name]}});state_receipts=[ordered]@{seed=$seedState;capped=$cappedState;relaxed=$relaxedState};save_lineage=$lineage;logs=[ordered]@{seed=Get-Artifact $seedLog;capped=Get-Artifact $cappedLog;relaxed=Get-Artifact $relaxedLog};explicit_non_claims=$nonClaims}
$result['candidate_materialization']=Get-Artifact $SourceMaterializationPath
$result['candidate_created_by_harness']=$false
$result['library_activations']=@($stages|ForEach-Object {$_.terminal})
$result['dependency_payload_bytes_copied']=0
$result['archive_links_created']=0
$result['resource_context']=[ordered]@{expected_peak_memory_bytes=$resources.peak_memory_bytes;max_new_output_bytes=$resources.max_new_output_bytes;shared_alias_bytes=$resources.shared_alias_bytes;memory_enforcement='sampled-watchdog-not-hard-cap'}
$result['process_inventory']=@($resources.runs)
Assert-Exact 'candidate after execution' (Get-Sha $candidateZip) ([string]$candidateInput.receipt.archive_sha256)
foreach($stage in $stages){foreach($entry in $stage.archive_hashes.GetEnumerator()){
  Assert-Exact ('library input after '+$stage.name+': '+$entry.Key) (Get-Sha (Join-Path $library $entry.Key)) ([string]$entry.Value)
}}
Assert-MIR441CleanTrackedSource -RepoRoot $repo
Assert-Exact 'source after execution' ((& git -C $repo rev-parse HEAD).Trim()) $sourceCommit
Assert-Exact 'engine after execution' (Get-Sha $engine) $engineSha
Write-MIRNativeProbeResult -Context $resources -Record $result
$result|ConvertTo-Json -Depth 40;Write-Output "Evidence: $($resources.root)"
