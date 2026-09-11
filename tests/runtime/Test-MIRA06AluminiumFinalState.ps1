# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [ValidateSet('bob','angel','combined')][string]$Profile='bob',
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$CandidateZip='',
  [string]$ModsDir='C:\Projects\Factorio\testmods\2.1',
  [string]$OutputRoot=''
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
$modsRoot=(Resolve-Path -LiteralPath $ModsDir).Path
$locks=[ordered]@{
  'boblibrary_3.0.0.zip'='49EAE2D4D8E58EBD28BAFDB7E71D5307CBCE2077E0642440ED7EC527D466FFC4'
  'bobores_3.0.0.zip'='7F8E33E35F59BB3F2CD72E3AB2FED30D1C2AE9C117E3731324AC307D9965082B'
  'bobplates_3.0.1.zip'='503D7BF6E88DA1F99463AC00CEC959C2003B2701D80DC4A564CF2EC3920AC8AF'
  'angelsrefining_2.1.2.zip'='AF5E79E35E591F68D52F13EDA082950E10AC98A4B7722B3F568D0211E3FEB813'
  'angelsrefininggraphics_2.1.0.zip'='79F373BC628F619EDE3B1875827172390D2C3F5EAB56310F6F1572C4553CB6EF'
  'angelspetrochem_2.1.2.zip'='9B4CC14156CF16C9F41784108CCA5E767180A7330B1AF23A387231653CE10A49'
  'angelspetrochemgraphics_2.1.0.zip'='DECDC2FCD5BBBDEF70784943C142C30FAA7294B98E814296C5D44D09A9DE4790'
  'angelssmelting_2.1.1.zip'='1DFCDD77D075FD545CFEE74BD8A6443E7E90B133D3832FDD47649C84892243A9'
  'angelssmeltinggraphics_2.1.0.zip'='EBEF8D1F6F13F84B242DF295CE9FAB9618ED90B4C52852A0B4345908A88D5D35'
}
$profiles=@{
  bob=[ordered]@{archives=@('boblibrary_3.0.0.zip','bobores_3.0.0.zip','bobplates_3.0.1.zip');mods=@('boblibrary','bobores','bobplates');official=@('base');output='build/tests/mir42-a06-bob-aluminium-final-state'}
  angel=[ordered]@{archives=@('angelsrefining_2.1.2.zip','angelsrefininggraphics_2.1.0.zip','angelspetrochem_2.1.2.zip','angelspetrochemgraphics_2.1.0.zip','angelssmelting_2.1.1.zip','angelssmeltinggraphics_2.1.0.zip');mods=@('angelsrefining','angelsrefininggraphics','angelspetrochem','angelspetrochemgraphics','angelssmelting','angelssmeltinggraphics');official=@('base');output='build/tests/mir42-a06-angel-aluminium-final-state'}
  combined=[ordered]@{archives=@('boblibrary_3.0.0.zip','bobores_3.0.0.zip','bobplates_3.0.1.zip','angelsrefining_2.1.2.zip','angelsrefininggraphics_2.1.0.zip','angelspetrochem_2.1.2.zip','angelspetrochemgraphics_2.1.0.zip','angelssmelting_2.1.1.zip','angelssmeltinggraphics_2.1.0.zip');mods=@('boblibrary','bobores','bobplates','angelsrefining','angelsrefininggraphics','angelspetrochem','angelspetrochemgraphics','angelssmelting','angelssmeltinggraphics');official=@('base','elevated-rails','quality','recycler','space-age');output='build/tests/mir42-a06-bob-angel-aluminium-final-state'}
}
$spec=$profiles[$Profile]
if([string]::IsNullOrWhiteSpace($OutputRoot)){$OutputRoot=[string]$spec.output}
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$buildRoot=[IO.Path]::GetFullPath((Join-Path $repo 'build'))+[IO.Path]::DirectorySeparatorChar
if(-not $output.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'A06 Aluminium probe outputs must remain under build.'}
function Assert-A06([bool]$Condition,[string]$Message){if(-not $Condition){throw "[mir-a06-aluminium] $Message"}}
function Get-A06Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Get-A06Artifact([string]$Path){$full=(Resolve-Path -LiteralPath $Path).Path;Assert-A06 ($full.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) "artifact outside repository $full";[ordered]@{path=$full.Substring($repo.Length+1).Replace('\','/');bytes=(Get-Item -LiteralPath $full).Length;raw_sha256=Get-A06Sha $full}}
function Get-A06Rows([string]$Log,[string]$Marker){@((Get-Content -LiteralPath $Log)|ForEach-Object{$match=[regex]::Match($_,[regex]::Escape($Marker)+'.*$');if($match.Success){$match.Value}}|Where-Object{$_})}
$engineSha='710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8'
Assert-A06 ((Get-A06Sha $engine) -ceq $engineSha) 'requires the exact Steam F210 engine binary.'
$version=(& $engine --version|Out-String)
Assert-A06 ($LASTEXITCODE -eq 0 -and $version -match 'Version: 2[.]1[.]17') 'requires Factorio 2.1.17.'
$engineVersion=([regex]::Match($version,'Version:\s+2[.]1[.]17[^\r\n]*').Value).Trim();Assert-A06 (-not [string]::IsNullOrWhiteSpace($engineVersion)) 'could not bind engine version.'
$sourceCommit=(& git -C $repo rev-parse HEAD).Trim();$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim();Assert-A06 ($sourceCommit -match '^[0-9a-f]{40}$' -and $sourceTree -match '^[0-9a-f]{40}$') 'requires source commit/tree identities.'
$sourceChanges=@(& git -C $repo status --porcelain --untracked-files=all -- src/mod);$allowedAliasSources=@('src/mod/families/modern/prototypes/streams/productivity.lua','src/mod/package-source.json');$sourceChangePaths=@($sourceChanges|ForEach-Object{$_.Substring(3).Replace('\','/')}|Sort-Object -CaseSensitive);$sourceRootClean=($sourceChangePaths.Count -eq 0);$boundedDirtyAliasSources=(($sourceChangePaths -join '|') -ceq ($allowedAliasSources -join '|'));Assert-A06 ($sourceRootClean -or $boundedDirtyAliasSources) "requires either a clean src/mod root or exactly the bounded A06 Aluminium alias and refreshed manifest changes: $($sourceChanges -join '; ')";$aliasSourcePath=Join-Path $repo $allowedAliasSources[0];$aliasSourceSha=Get-A06Sha $aliasSourcePath;$sourceManifestPath=Join-Path $repo $allowedAliasSources[1];$sourceManifestSha=Get-A06Sha $sourceManifestPath;$sourceMode=if($sourceRootClean){'clean-src-mod-root'}else{'bounded-dirty-a06-alias'}
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/validation/SettingsOverrides.ps1')
if([string]::IsNullOrWhiteSpace($CandidateZip)){$candidate=New-MIR4TargetPackage -RepoRoot $repo -Target f210 -CandidateId ('A06-'+$Profile.ToUpperInvariant()+'-ALUMINIUM-'+[guid]::NewGuid().ToString('N').Substring(0,8).ToUpperInvariant()) -SourceVersion '4.2.0' -DistributionVersion '4.2.21000' -OutputRoot 'build/a06-aluminium-probe/packages';$CandidateZip=[string]$candidate.archive_path}
$candidateZip=(Resolve-Path -LiteralPath $CandidateZip).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($candidateZip);try{$forbidden=@($zip.Entries|Where-Object{$_.FullName -match '(^|/)(fixtures|tests|docs|[.]mir|build|dist)(/|$)'});if($forbidden.Count -ne 0){throw "candidate contains package-excluded path $($forbidden[0].FullName)"}}finally{$zip.Dispose()}
$run=Join-Path $output ([guid]::NewGuid().ToString('N'));$mods=Join-Path $run 'mods';New-Item -ItemType Directory -Force -Path $mods,(Join-Path $run 'userdata')|Out-Null
Copy-Item -LiteralPath $candidateZip -Destination (Join-Path $mods ([IO.Path]::GetFileName($candidateZip)))
$archiveArtifacts=@();foreach($name in @($spec.archives)){$source=Join-Path $modsRoot $name;Assert-A06 (Test-Path -LiteralPath $source -PathType Leaf) "missing $Profile lock $source";Assert-A06 ((Get-A06Sha $source) -ceq $locks[$name]) "$Profile lock hash differs $name";Copy-Item -LiteralPath $source -Destination $mods;$archiveArtifacts+=Get-A06Artifact (Join-Path $mods $name)}
$fixture=Join-Path $repo 'fixtures/assert-a06-aluminium-final-state';Assert-A06 (Test-Path -LiteralPath $fixture -PathType Container) 'Aluminium observer fixture is absent.';Publish-MIRModDirectoryArchive -Source $fixture -Name 'mir-fixture-assert-a06-aluminium-final-state' -Version '0.1.0' -ModsDir $mods|Out-Null
Initialize-MIRSettingsOverrideMod -ModsDir $mods -FactorioVersion '2.1';Set-CopiedStartupSettingDefaults -ModsDir $mods -Overrides @{'mir-debug-generation-report'=$true;'ips-enable-research_material_aluminium'=$true};Set-CopiedMIRSettingsProfileDefault -ModsDir $mods -Settings @{'ips-enable-research_material_aluminium'=$true};Complete-MIRSettingsOverrideMod -ModsDir $mods
$officialMods=@('base','elevated-rails','quality','recycler','space-age');$modNames=@($officialMods+@('more-infinite-research')+@($spec.mods)+@('mir-fixture-assert-a06-aluminium-final-state','mir-validation-settings-overrides'));$modList=[ordered]@{mods=@($modNames|ForEach-Object{[ordered]@{name=$_;enabled=($_ -in @($spec.official) -or $_ -notin $officialMods)}})}
[IO.File]::WriteAllText((Join-Path $mods 'mod-list.json'),(($modList|ConvertTo-Json -Depth 10)+"`n"),[Text.UTF8Encoding]::new($false))
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent)-Parent)-Parent;[IO.File]::WriteAllText((Join-Path $run 'config.ini'),"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($run.Replace('\','/'))/userdata`n",[Text.UTF8Encoding]::new($false))
$save=Join-Path $run ("a06-$Profile-aluminium-final-state.zip")
$start=[Diagnostics.ProcessStartInfo]::new($engine);$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true;$start.Environment['SteamAppId']='427520';$start.Environment['SteamGameId']='427520';foreach($argument in @('--config',(Join-Path $run 'config.ini'),'--mod-directory',$mods,'--create',$save)){$start.ArgumentList.Add($argument)}
$process=[Diagnostics.Process]::Start($start);try{$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();if(-not $process.WaitForExit(180000)){$process.Kill($true);throw "A06 $Profile Aluminium probe timed out: $run"};$engineText=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult();[IO.File]::WriteAllText((Join-Path $run 'engine.log'),$engineText,[Text.UTF8Encoding]::new($false));if($process.ExitCode -ne 0){throw "A06 $Profile Aluminium engine failed: $run`n$($engineText.Substring([Math]::Max(0,$engineText.Length-2500)))"}}finally{$process.Dispose()}
$factorioLog=Join-Path $run 'userdata/factorio-current.log';Assert-A06 (Test-Path -LiteralPath $factorioLog -PathType Leaf) 'Factorio log is absent.';Copy-Item -LiteralPath $factorioLog -Destination (Join-Path $run 'factorio.log');$factorioEvidence=Join-Path $run 'factorio.log';$rows=Get-A06Rows $factorioEvidence '[mir-a06-aluminium]'
$expectedBob=if($Profile -in @('bob','combined')){'true'}else{'false'};$expectedAngel=if($Profile -in @('angel','combined')){'true'}else{'false'};$expectedProfile="[mir-a06-aluminium] PROFILE name=$Profile bobplates=$expectedBob angelssmelting=$expectedAngel"
Assert-A06 (@($rows|Where-Object{$_ -ceq $expectedProfile}).Count -eq 1) "exact $Profile profile marker is absent."
Assert-A06 (@($rows|Where-Object{$_.StartsWith('[mir-a06-aluminium] SUMMARY ')}).Count -eq 1) 'final-state summary marker is absent.'
Assert-A06 (@($rows|Where-Object{$_ -ceq "[mir-a06-aluminium] RUNTIME profile=$Profile state=loaded observer=read-only"}).Count -eq 1) "exact $Profile runtime observation marker is absent."
$expectedCombinedAssertion='[mir-a06-aluminium] ASSERTION profile=combined status=withheld technology=absent routes=bob-aluminium-plate,angels-plate-aluminium,angels-plate-aluminium-2 owners=none hidden=bob-aluminium-plate permission-enabled=angels-plate-aluminium,angels-plate-aluminium-2 permission-unset=angels-ingot-aluminium,angels-liquid-molten-aluminium,angels-roll-aluminium presentation=omitted progression=omitted'
if($Profile -eq 'combined'){Assert-A06 (@($rows|Where-Object{$_ -ceq $expectedCombinedAssertion}).Count -eq 1) 'exact combined withheld final-state assertion marker is absent.'}else{Assert-A06 (@($rows|Where-Object{$_ -and $_.StartsWith("[mir-a06-aluminium] ASSERTION profile=$Profile ")}).Count -eq 1) "exact $Profile final-state assertion marker is absent."}
$compilerRows=@((Get-Content -LiteralPath $factorioEvidence)|ForEach-Object{$match=[regex]::Match($_,'\[more-infinite-research\] (?:report|audit) .*');if($match.Success -and $match.Value -match '(?i)(aluminium|aluminum)'){$match.Value}})
$rawMaterialRouteOmissionRows=@((Get-Content -LiteralPath $factorioEvidence)|ForEach-Object{$match=[regex]::Match($_,'\[more-infinite-research\] Material route omitted .*');if($match.Success -and $match.Value -match '(?i)(aluminium|aluminum)'){$match.Value}})
$expectedOmissionRows=@()
$streamSkipRows=@()
if($Profile -eq 'combined'){
  $expectedOmissionRows=@('[more-infinite-research] Material route omitted recipe=bob-aluminium-plate reason=potential-return-path:angels-solid-carbon','[more-infinite-research] Material route omitted recipe=angels-plate-aluminium reason=potential-return-path:angels-liquid-molten-aluminium','[more-infinite-research] Material route omitted recipe=angels-plate-aluminium-2 reason=potential-return-path:angels-roll-aluminium')
  foreach($expectedOmission in $expectedOmissionRows){Assert-A06 (@($rawMaterialRouteOmissionRows|Where-Object{$_ -ceq $expectedOmission}).Count -eq 1) "exact combined omission row is absent: $expectedOmission"}
  Assert-A06 ($rawMaterialRouteOmissionRows.Count -eq $expectedOmissionRows.Count) 'combined Aluminium omission rows include an unexpected route.'
  $streamSkipRows=@($compilerRows|Where-Object{$_ -match 'kind=stream' -and $_ -match 'key=research_material_aluminium' -and $_ -match 'status=skipped' -and $_ -match 'reason=no_matching_recipes' -and $_ -match 'effects=0'})
  Assert-A06 ($streamSkipRows.Count -eq 2) 'combined Aluminium stream did not report both skipped no_matching_recipes records.'
}
function Select-A06Rows([string]$Prefix){@($rows|Where-Object{$_.StartsWith($Prefix)})}
$nonClaims=if($Profile -eq 'combined'){
  @('Combined profile is a withheld guard disposition: no stable Aluminium technology, presentation, progression, effect, or owner claim.','No gameplay progression, safety, balance, save, release, or public-support authority.')
}else{
  @('Prototype admission is bounded to the exact locked profile and asserted final routes.','No actual production gain, balance, predecessor upgrade, save continuity, release, or broader public-support claim.')
}
$observation=[ordered]@{schema=1;kind='MIR4A06AluminiumFinalStateObservationV1';profile=$Profile;observation_mode='post-finalizer-read-only';fixture_rows=[ordered]@{items=Select-A06Rows '[mir-a06-aluminium] ITEM ';recipes=Select-A06Rows '[mir-a06-aluminium] RECIPE ';machine_categories=Select-A06Rows '[mir-a06-aluminium] MACHINE_CATEGORY ';technologies=Select-A06Rows '[mir-a06-aluminium] TECHNOLOGY ';ownership=Select-A06Rows '[mir-a06-aluminium] OWNERS ';matching=Select-A06Rows '[mir-a06-aluminium] MATCHING ';assertion=Select-A06Rows '[mir-a06-aluminium] ASSERTION ';summary=Select-A06Rows '[mir-a06-aluminium] SUMMARY '};compiler_matching_or_omission_rows=$compilerRows;raw_material_route_omission_rows=$rawMaterialRouteOmissionRows;expected_withheld_omission_rows=$expectedOmissionRows;stream_skip_rows=$streamSkipRows;non_claims=$nonClaims}
$observationPath=Join-Path $run 'observation.json';[IO.File]::WriteAllText($observationPath,(($observation|ConvertTo-Json -Depth 20)+"`n"),[Text.UTF8Encoding]::new($false))
$fixtureFiles=@('info.json','data-final-fixes.lua','control.lua')
$resultStatus=if($Profile -eq 'combined'){'withheld-by-acyclic-guard'}else{'passed-bounded-prototype-admission'}
$dirtyAliasSource=$null;$dirtyAliasSourceSha=$null;$refreshedSourceManifest=$null;$refreshedSourceManifestSha=$null
if($boundedDirtyAliasSources){$dirtyAliasSource=$allowedAliasSources[0];$dirtyAliasSourceSha=$aliasSourceSha;$refreshedSourceManifest=$allowedAliasSources[1];$refreshedSourceManifestSha=$sourceManifestSha}
$sourceRecord=[ordered]@{commit=$sourceCommit;tree=$sourceTree;package_source_sha256=Get-A06Sha (Join-Path $repo 'src/mod/package-source.json');package_source_roots_clean=$sourceRootClean;source_mode=$sourceMode;bounded_dirty_alias_source=$dirtyAliasSource;bounded_dirty_alias_source_sha256=$dirtyAliasSourceSha;refreshed_source_manifest=$refreshedSourceManifest;refreshed_source_manifest_sha256=$refreshedSourceManifestSha}
$result=[ordered]@{schema=1;kind='MIR4A06AluminiumFinalStateProbeResultV1';status=$resultStatus;profile=$Profile;engine=[ordered]@{version=$engineVersion;executable_sha256=Get-A06Sha $engine};source=$sourceRecord;candidate=Get-A06Artifact $candidateZip;mod_archives=$archiveArtifacts;mod_list=Get-A06Artifact (Join-Path $mods 'mod-list.json');fixture=[ordered]@{path='fixtures/assert-a06-aluminium-final-state';files=@($fixtureFiles|ForEach-Object{Get-A06Artifact (Join-Path $fixture $_)})};harness=Get-A06Artifact $PSCommandPath;settings_override=Get-A06Artifact (Join-Path $mods 'mir-validation-settings-overrides_0.1.0.zip');save=Get-A06Artifact $save;logs=[ordered]@{engine=Get-A06Artifact (Join-Path $run 'engine.log');factorio=Get-A06Artifact $factorioEvidence};observation=Get-A06Artifact $observationPath;non_claims=@($observation.non_claims)}
$resultPath=Join-Path $run 'result.json';[IO.File]::WriteAllText($resultPath,(($result|ConvertTo-Json -Depth 20)+"`n"),[Text.UTF8Encoding]::new($false));$result|ConvertTo-Json -Depth 20;Write-Output "Evidence: $run"
