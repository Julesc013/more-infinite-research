# The maintenance scenario reuses the continuation profile's exact dependency
# releases. Its assertion fixture replaces that profile's fresh-game fixture.
function Get-MIR470K2CurrentProfileSpecification {
  param([Parameter(Mandatory)][string]$Path)
  $known=@(
    [pscustomobject]@{
      profile_file='k2-214-imersite-f210-470.json';engine_version='2.1.22'
      profile_sha256='106AB7A6BAEEDE8090CFBAC91CA3C3B7B8D8D470EB63AAEB14FC39ADB9D397A4'
      engine_sha256='D8C745FD4E8C901BF0FC250C4D0FF75B454987857C1AEAADF8E775F0E65A9E4B'
      runtime_api_sha256='B13B3F44B88546DFEB74D360666F565F065BB1A801EE63BCC2069A5F05A30C68'
      continuation_fixture_version='0.1.9';migration_fixture_version='0.1.4700';sentinel_fixture_version='0.1.4700'
    },
    [pscustomobject]@{
      profile_file='k2-214-imersite-f210-470-2123.json';engine_version='2.1.23'
      profile_sha256='DC6EE665BDE9D734CF325F1C91902914CE6D6EB79038C1F6A4D7A52425E2F788'
      engine_sha256='FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060'
      runtime_api_sha256='7660B692F1C199682DE4318250DE81B07B38266A935D1C37859DCB6A70E1D373'
      continuation_fixture_version='0.1.10';migration_fixture_version='0.1.4701';sentinel_fixture_version='0.1.4701'
    }
  )
  $matches=@($known|Where-Object {$_.profile_file-ceq[IO.Path]::GetFileName($Path)})
  if($matches.Count-ne1){throw '[mir470-k2-upgrade-profile-path]'}
  $spec=$matches[0]
  if((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash-cne$spec.profile_sha256){throw '[mir470-k2-upgrade-profile-hash]'}
  return $spec
}

function Read-MIR421K2UpgradeProfile {
  param([Parameter(Mandatory)][string]$Path,
    [ValidateSet('4.2.1','4.2.2','4.7.0')][string]$SourceVersion='4.2.1')
  $profile=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json -Depth 20
  $current470=$SourceVersion-ceq'4.7.0'
  $currentProfile=$null
  $engineVersion='2.1.21'
  if($current470){
    $currentProfile=Get-MIR470K2CurrentProfileSpecification -Path $Path
    $engineVersion=[string]$currentProfile.engine_version
  }
  if($profile.schema-ne1-or$profile.target-cne'f210'-or$profile.factorio_line-cne'2.1'-or
     $profile.engine_version-cne$engineVersion-or$profile.settings_mode-cne'Defaults') {throw '[mir421-k2-upgrade-profile]'}
  foreach($field in @('engine_sha256','runtime_api_sha256')){
    if([string]$profile.$field-cnotmatch'^[0-9A-F]{64}$'){throw '[mir421-k2-upgrade-engine-hash]'}
  }
  if($current470-and(
    [string]$profile.engine_sha256-cne$currentProfile.engine_sha256-or
    [string]$profile.runtime_api_sha256-cne$currentProfile.runtime_api_sha256)){
    throw '[mir470-k2-upgrade-engine-identity]'
  }
  $expected=[ordered]@{base=$engineVersion;'elevated-rails'=$engineVersion;quality=$engineVersion;recycler=$engineVersion;'space-age'=$engineVersion;
    flib='0.17.2';'k2so-assets'='1.0.7';Krastorio2=$(if($current470){'2.1.4'}else{'2.1.3'});'Krastorio2-spaced-out'=$(if($current470){'2.0.19'}else{'2.0.13'});
    Krastorio2Assets='2.1.0';Krastorio2MenuSimulations='2.1.0';'xy-k2so-enhancements-nulls-fork'='0.8.3';
    'more-infinite-research'=$(if($current470){'4.7.21000'}else{'4.2.2100'+([version]$SourceVersion).Build});'mir-fixture-assert-k2-213-imersite-continuation'=$(if($current470){@([string]$currentProfile.continuation_fixture_version)}elseif($SourceVersion-ceq'4.2.2'){@('0.1.4')}else{@('0.1.3','0.1.4')})}
  # Each retained profile selects an exact dependency closure. The fresh-game
  # fixture is excluded below and replaced by the staged upgrade fixture.
  if(@($profile.mods).Count-ne$expected.Count){throw '[mir421-k2-upgrade-selection]'}
  foreach($name in $expected.Keys){
    $rows=@($profile.mods|Where-Object name -CEQ $name)
    if($rows.Count-ne1-or$rows[0].enabled-isnot[bool]-or-not$rows[0].enabled-or$rows[0].version-cnotin@($expected[$name])){throw "[mir421-k2-upgrade-selection] $name"}
  }
  $builtins=@('base','elevated-rails','quality','recycler','space-age')
  $dependencies=@($profile.mods|Where-Object {$_.name-cnotin$builtins-and$_.name-cne'more-infinite-research'-and$_.name-cne'mir-fixture-assert-k2-213-imersite-continuation'})
  if(@($profile.archive_sha256.PSObject.Properties).Count-ne$dependencies.Count){throw '[mir421-k2-upgrade-archive-count]'}
  $inputs=@(foreach($row in $dependencies){
    $filename=$row.name+'_'+$row.version+'.zip'
    $property=$profile.archive_sha256.PSObject.Properties[$filename]
    if($null-eq$property-or[string]$property.Value-cnotmatch'^[0-9A-F]{64}$'){throw "[mir421-k2-upgrade-archive-hash] $filename"}
    [pscustomobject]@{file_name=$filename;expected_sha256=[string]$property.Value;identity=@{name=$row.name;version=$row.version}}
  })
  return [pscustomobject]@{profile=$profile;inputs=$inputs;source_version=$SourceVersion;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash;current_profile=$currentProfile}
}

function Assert-MIR421K2UpgradeTransition {
  param([string]$Target,[string]$FromVersion,[string]$ToVersion,[string]$FixtureName,[string]$Archetype,
    [bool]$SpaceIsFake,[string[]]$SourceOnlyFixtureNames=@(),
    [ValidateSet('4.2.1','4.2.2','4.7.0')][string]$SourceVersion='4.2.1')
  if($SourceVersion-ceq'4.7.0'){
    $expectedFrom='4.6.21000';$expectedTo='4.7.21000';$expectedFixture='assert-upgrade-k2-imersite-4-6-21000-to-4-7-21000'
  }else{
    $patch=([version]$SourceVersion).Build
    $expectedFrom='4.2.2100'+($patch-1);$expectedTo='4.2.2100'+$patch
    $expectedFixture='assert-upgrade-k2-imersite-'+$expectedFrom.Replace('.','-')+'-to-'+$expectedTo.Replace('.','-')
  }
  if($Target-cne'f210'-or$FromVersion-cne$expectedFrom-or$ToVersion-cne$expectedTo-or
     $FixtureName-cne$expectedFixture-or$Archetype-or$SpaceIsFake-or$SourceOnlyFixtureNames.Count){
    throw '[mir421-k2-upgrade-transition]'
  }
}

function Get-MIR470K2OwnedSpeedSentinelFixture {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$FixtureName,[Parameter(Mandatory)][string]$SourceVersion)
  if($FixtureName-cne'assert-upgrade-k2-imersite-4-6-21000-to-4-7-21000'-or$SourceVersion-cne'4.7.0'){
    throw '[mir470-k2-owned-speed-sentinel-fixture-admission]'
  }
  $directory=Join-Path $RepoRoot 'fixtures/aaa-mir47-owned-speed-sentinel'
  $infoPath=Join-Path $directory 'info.json'
  $controlPath=Join-Path $directory 'control.lua'
  if(-not(Test-Path -LiteralPath $infoPath -PathType Leaf)-or-not(Test-Path -LiteralPath $controlPath -PathType Leaf)){
    throw '[mir470-k2-owned-speed-sentinel-fixture-files]'
  }
  $info=Get-Content -LiteralPath $infoPath -Raw|ConvertFrom-Json
  if([string]$info.name-cne'aaa-mir47-owned-speed-sentinel'-or[string]$info.version-cne'0.1.4700'-or[string]$info.factorio_version-cne'2.1'-or@($info.dependencies)-cnotcontains'base = 2.1.22'){
    throw '[mir470-k2-owned-speed-sentinel-fixture-identity]'
  }
  [pscustomobject]@{
    name=[string]$info.name;version=[string]$info.version;directory=$directory
    info_sha256=(Get-FileHash -LiteralPath $infoPath -Algorithm SHA256).Hash
    control_sha256=(Get-FileHash -LiteralPath $controlPath -Algorithm SHA256).Hash
  }
}

function New-MIR470K2CurrentMigrationFixtureSpecialization {
  param(
    [Parameter(Mandatory)][string]$StagedMigrationFixtureDirectory,
    [Parameter(Mandatory)]$OwnedSpeedSentinelFixture,
    [Parameter(Mandatory)][string]$FixtureSourcesDirectory,
    [Parameter(Mandatory)]$CurrentProfile
  )
  $migrationInfoPath=Join-Path $StagedMigrationFixtureDirectory 'info.json'
  $migrationControlPath=Join-Path $StagedMigrationFixtureDirectory 'control.lua'
  $migrationInfo=Get-Content -LiteralPath $migrationInfoPath -Raw|ConvertFrom-Json -Depth 20
  $migrationControl=[IO.File]::ReadAllText($migrationControlPath)
  $expectedMigrationVersion=[string]$CurrentProfile.migration_fixture_version
  $expectedSentinelVersion=[string]$CurrentProfile.sentinel_fixture_version
  if([string]$migrationInfo.name-cne'mir-fixture-assert-k2-imersite-460-to-470-upgrade'-or[string]$migrationInfo.factorio_version-cne'2.1' -or
     @($migrationInfo.dependencies).Count-ne4-or@($migrationInfo.dependencies)-cnotcontains'more-infinite-research >= 4.6.21000' -or
     @($migrationInfo.dependencies)-cnotcontains'Krastorio2 = 2.1.4' -or@($migrationInfo.dependencies)-cnotcontains'Krastorio2-spaced-out = 2.0.19'){
    throw '[mir470-k2-current-staged-migration-fixture-identity]'
  }
  if([string]$CurrentProfile.engine_version-ceq'2.1.22'){
    if([string]$migrationInfo.version-cne'0.1.4700'-or@($migrationInfo.dependencies)-cnotcontains'base = 2.1.22'-or
       -not$migrationControl.Contains('base = "2.1.22"')-or-not$migrationControl.Contains('[fixture_name] = "0.1.4700"')-or-not$migrationControl.Contains('owned_speed_sentinel_version = "0.1.4700"')){
      throw '[mir470-k2-current-retained-migration-fixture]'
    }
    return [pscustomobject]@{migration=[pscustomobject]@{directory=$StagedMigrationFixtureDirectory;version='0.1.4700';info_sha256=(Get-FileHash -LiteralPath $migrationInfoPath -Algorithm SHA256).Hash;control_sha256=(Get-FileHash -LiteralPath $migrationControlPath -Algorithm SHA256).Hash};owned_speed_sentinel=$OwnedSpeedSentinelFixture;specialized=$false}
  }
  if([string]$CurrentProfile.engine_version-cne'2.1.23'-or$expectedMigrationVersion-cne'0.1.4701'-or$expectedSentinelVersion-cne'0.1.4701'){
    throw '[mir470-k2-current-profile-specialization]'
  }
  if([string]$migrationInfo.version-cne'0.1.4700'-or@($migrationInfo.dependencies)-cnotcontains'base = 2.1.22' -or
     -not$migrationControl.Contains('base = "2.1.22"')-or-not$migrationControl.Contains('[fixture_name] = "0.1.4700"')-or-not$migrationControl.Contains('owned_speed_sentinel_version = "0.1.4700"')){
    throw '[mir470-k2-current-staged-migration-anchor]'
  }
  $migrationInfo.version=$expectedMigrationVersion
  $migrationInfo.dependencies=@($migrationInfo.dependencies|ForEach-Object {if([string]$_-ceq'base = 2.1.22'){'base = 2.1.23'}else{[string]$_}})
  [IO.File]::WriteAllText($migrationInfoPath,($migrationInfo|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
  $migrationControl=$migrationControl.Replace('base = "2.1.22"','base = "2.1.23"').Replace('[fixture_name] = "0.1.4700"','[fixture_name] = "0.1.4701"').Replace('owned_speed_sentinel_version = "0.1.4700"','owned_speed_sentinel_version = "0.1.4701"')
  [IO.File]::WriteAllText($migrationControlPath,$migrationControl,[Text.UTF8Encoding]::new($false))
  $sentinelStage=Join-Path $FixtureSourcesDirectory ('aaa-mir47-owned-speed-sentinel_'+$expectedSentinelVersion)
  if(Test-Path -LiteralPath $sentinelStage){throw '[mir470-k2-current-staged-sentinel-fresh]'}
  Copy-Item -LiteralPath $OwnedSpeedSentinelFixture.directory -Destination $sentinelStage -Recurse
  $sentinelInfoPath=Join-Path $sentinelStage 'info.json'
  $sentinelControlPath=Join-Path $sentinelStage 'control.lua'
  $sentinelInfo=Get-Content -LiteralPath $sentinelInfoPath -Raw|ConvertFrom-Json -Depth 20
  if([string]$sentinelInfo.name-cne'aaa-mir47-owned-speed-sentinel'-or[string]$sentinelInfo.version-cne'0.1.4700'-or@($sentinelInfo.dependencies)-cnotcontains'base = 2.1.22'){
    throw '[mir470-k2-current-staged-sentinel-anchor]'
  }
  $sourceControlHash=[string]$OwnedSpeedSentinelFixture.control_sha256
  $sentinelInfo.version=$expectedSentinelVersion
  $sentinelInfo.dependencies=@($sentinelInfo.dependencies|ForEach-Object {if([string]$_-ceq'base = 2.1.22'){'base = 2.1.23'}else{[string]$_}})
  [IO.File]::WriteAllText($sentinelInfoPath,($sentinelInfo|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
  if((Get-FileHash -LiteralPath $sentinelControlPath -Algorithm SHA256).Hash-cne$sourceControlHash){throw '[mir470-k2-current-staged-sentinel-control]'}
  return [pscustomobject]@{
    migration=[pscustomobject]@{directory=$StagedMigrationFixtureDirectory;version=$expectedMigrationVersion;info_sha256=(Get-FileHash -LiteralPath $migrationInfoPath -Algorithm SHA256).Hash;control_sha256=(Get-FileHash -LiteralPath $migrationControlPath -Algorithm SHA256).Hash}
    owned_speed_sentinel=[pscustomobject]@{name=[string]$sentinelInfo.name;version=$expectedSentinelVersion;directory=$sentinelStage;info_sha256=(Get-FileHash -LiteralPath $sentinelInfoPath -Algorithm SHA256).Hash;control_sha256=$sourceControlHash}
    specialized=$true
  }
}

function Assert-MIR470K2OwnedSpeedSentinelConfigurationOrder {
  param([Parameter(Mandatory)][string]$Text)
  $sentinel='[mir-owned-speed-sentinel] target-restored event=1'
  $mir='[more-infinite-research] Maximum-level state'
  $sentinelIndex=$Text.IndexOf($sentinel,[StringComparison]::Ordinal)
  if($sentinelIndex-lt0){throw '[mir470-k2-owned-speed-sentinel-configuration-order] missing companion restoration'}
  $mirIndex=$Text.IndexOf($mir,$sentinelIndex,[StringComparison]::Ordinal)
  if($mirIndex-lt0){throw '[mir470-k2-owned-speed-sentinel-configuration-order] no later MIR maximum-level callback observation'}
}

function Assert-MIR421K2UpgradeMarker {
  param([string]$Text,[ValidateSet('source','upgrade','reload')][string]$Stage,[ValidateSet(0,3)][int]$Cap=3,
    [ValidateSet('4.2.1','4.2.2','4.7.0')][string]$SourceVersion='4.2.1')
  $token=$SourceVersion.Replace('.','')
  if($Text-notmatch ('\[mir-fixture\] K2-'+$token+' maintenance state verified stage='+$Stage+';cap='+$Cap+'(?:\r?\n|$)')){throw "[mir421-k2-upgrade-$Stage-marker]"}
}

function Assert-MIR470K2CurrentUpgradeProfilePath {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path)
  $spec=Get-MIR470K2CurrentProfileSpecification -Path $Path
  $expected=[IO.Path]::GetFullPath((Join-Path $RepoRoot ('fixtures/run-profiles/'+$spec.profile_file)))
  $actual=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
  if($actual-cne$expected){throw '[mir470-k2-upgrade-profile-path]'}
  return $spec
}

function Assert-MIR470K2CurrentPredecessorArchive {
  param([Parameter(Mandatory)][string]$Path)
  if((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash-cne'5A1CA84B0AA8E9690B9095DB12DC991C26EF9081481E2A530B953F47384A945A'){
    throw '[mir470-k2-published-460-archive-hash]'
  }
}

function Assert-MIR470K2FullStateActiveMods {
  param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)][object[]]$ExpectedSelection,[Parameter(Mandatory)][ValidateSet('source','upgrade','reload')][string]$Stage)
  $expected=[ordered]@{}
  foreach($row in @($ExpectedSelection|Where-Object {[bool]$_.enabled})){$expected[[string]$row.name]=[string]$row.version}
  $actual=[ordered]@{}
  foreach($property in @($Snapshot.active_mods.PSObject.Properties)){$actual[[string]$property.Name]=[string]$property.Value}
  if($expected.Count-ne$actual.Count){throw ('[mir470-k2-full-state-active-mod-count:{0}]' -f $Stage)}
  foreach($name in $expected.Keys){if(-not$actual.Contains($name)-or$actual[$name]-cne$expected[$name]){throw ('[mir470-k2-full-state-active-mod:{0}:{1}]' -f $Stage,$name)}}
  foreach($name in @('Krastorio2','Krastorio2-spaced-out','more-infinite-research')){if(-not$actual.Contains($name)){throw ('[mir470-k2-full-state-required-mod:{0}:{1}]' -f $Stage,$name)}}
  if($actual['Krastorio2']-cne'2.1.4'-or$actual['Krastorio2-spaced-out']-cne'2.0.19'){throw ('[mir470-k2-full-state-upstream:{0}]' -f $Stage)}
  return [ordered]@{active_mods=$actual}
}

# Use the shared settings writer. Cap three deliberately has no override so
# that the published default is observed; zero is an explicit test setting.
function New-MIR421K2CapOverride {
  param([string]$Root,[ValidateSet(0,3)][int]$Cap)
  if($Cap-eq3){return}
  Initialize-MIRSettingsOverrideMod -ModsDir $Root -FactorioVersion '2.1'
  Set-CopiedStartupSettingDefaults -ModsDir $Root -Overrides @{'ips-max-level-research_material_imersite'=0}
  $source=Join-Path $Root 'mir-validation-settings-overrides'
  $path=Join-Path $source 'info.json'
  $info=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
  $info=[ordered]@{name=$info.name;version='0.1.210';title=$info.title;author=$info.author;factorio_version=$info.factorio_version;dependencies=@($info.dependencies)}
  [IO.File]::WriteAllText($path,($info|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  return $source
}
