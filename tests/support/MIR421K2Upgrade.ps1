# The maintenance scenario reuses the continuation profile's exact dependency
# releases. Its assertion fixture replaces that profile's fresh-game fixture.
function Read-MIR421K2UpgradeProfile {
  param([Parameter(Mandatory)][string]$Path)
  $profile=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json -Depth 20
  if($profile.schema-ne1-or$profile.target-cne'f210'-or$profile.factorio_line-cne'2.1'-or
     $profile.engine_version-cne'2.1.21'-or$profile.settings_mode-cne'Defaults') {throw '[mir421-k2-upgrade-profile]'}
  foreach($field in @('engine_sha256','runtime_api_sha256')){
    if([string]$profile.$field-cnotmatch'^[0-9A-F]{64}$'){throw '[mir421-k2-upgrade-engine-hash]'}
  }
  $expected=[ordered]@{base='2.1.21';'elevated-rails'='2.1.21';quality='2.1.21';recycler='2.1.21';'space-age'='2.1.21';
    flib='0.17.2';'k2so-assets'='1.0.7';Krastorio2='2.1.3';'Krastorio2-spaced-out'='2.0.13';
    Krastorio2Assets='2.1.0';Krastorio2MenuSimulations='2.1.0';'xy-k2so-enhancements-nulls-fork'='0.8.3';
    'more-infinite-research'='4.2.21001';'mir-fixture-assert-k2-213-imersite-continuation'='0.1.3'}
  if(@($profile.mods).Count-ne$expected.Count){throw '[mir421-k2-upgrade-selection]'}
  foreach($name in $expected.Keys){
    $rows=@($profile.mods|Where-Object name -CEQ $name)
    if($rows.Count-ne1-or$rows[0].enabled-isnot[bool]-or-not$rows[0].enabled-or$rows[0].version-cne$expected[$name]){throw "[mir421-k2-upgrade-selection] $name"}
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
  return [pscustomobject]@{profile=$profile;inputs=$inputs;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
}

function Assert-MIR421K2UpgradeTransition {
  param([string]$Target,[string]$FromVersion,[string]$ToVersion,[string]$FixtureName,[string]$Archetype,
    [bool]$SpaceIsFake,[string[]]$SourceOnlyFixtureNames=@())
  if($Target-cne'f210'-or$FromVersion-cne'4.2.21000'-or$ToVersion-cne'4.2.21001'-or
     $FixtureName-cne'assert-upgrade-k2-imersite-4-2-21000-to-4-2-21001'-or$Archetype-or$SpaceIsFake-or$SourceOnlyFixtureNames.Count){
    throw '[mir421-k2-upgrade-transition]'
  }
}

function Assert-MIR421K2UpgradeMarker {
  param([string]$Text,[ValidateSet('source','upgrade','reload')][string]$Stage,[ValidateSet(0,3)][int]$Cap=3)
  if(-not$Text.Contains("[mir-fixture] K2-421 maintenance state verified stage=$Stage;cap=$Cap")){throw "[mir421-k2-upgrade-$Stage-marker]"}
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
