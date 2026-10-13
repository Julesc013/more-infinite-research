# Optional native scenario inputs for the existing manifest-driven upgrade runner.
function Assert-MIR42CompleteCatalogueUpgradeMarker {
  param([Parameter(Mandatory)][string]$Text)
  $markers=[regex]::Matches($Text,'\[mir-fixture\] complete (?:Space Age|research) state retained technologies=(?<technologies>[0-9]+) recipes=(?<recipes>[0-9]+)')
  if($markers.Count-eq0-or @($markers|Where-Object {[int]$_.Groups['technologies'].Value-lt3-or[int]$_.Groups['recipes'].Value-lt1}).Count){
    throw '[mir42-complete-catalogue-upgrade-marker] Full-state oracle did not execute successfully.'
  }
}

function Set-MIR421ModernBaseUpgradeFixtureIdentity {
  param([Parameter(Mandatory)][string]$FixtureDirectory,
    [Parameter(Mandatory)][ValidateSet('f210','f200','f110','f100')][string]$Target,
    [ValidateSet('4.2.1','4.2.2','4.2.3','4.3.0','4.3.1')][string]$SourceVersion='4.2.1',
    [AllowEmptyString()][string]$FromVersion='',
    [switch]$SpaceIsFake,
    [switch]$SpaceAge,
    [switch]$HistoricalSettingsOracle)
  # Only the disposable prepared fixture changes. Identity includes the
  # predecessor when 4.2.2 tests both CCC00 -> CCC02 and CCC01 -> CCC02:
  # their specialized control.lua bytes differ and must never share a library
  # archive name/version.
  if($SpaceIsFake -and $Target -cnotin @('f210','f200')){throw '[mir421-sif-target]'}
  if($SpaceAge -and ($SpaceIsFake -or $Target-cne'f210')){throw '[mir422-space-age-fixture-target]'}
  $code=$Target.Substring(1)
  $source=[version]$SourceVersion
  $sourcePatch=$source.Build
  if([string]::IsNullOrWhiteSpace($FromVersion)){
    $FromVersion=if($source.Minor-eq3){'4.2.'+$code+'02'}else{'4.2.'+$code+($sourcePatch-1).ToString('00')}
  }
  # Published 4.1.20000 is a deliberately narrow, independently authenticated
  # F200 predecessor for the 4.3.0 Full preservation fixture. It receives a
  # distinct disposable fixture version and is never a 4.2 maintenance row.
  $published410F200=[bool]($Target-ceq'f200'-and$SourceVersion-ceq'4.3.0'-and$FromVersion-ceq'4.1.20000'-and-not$SpaceIsFake-and-not$SpaceAge-and-not$HistoricalSettingsOracle)
  $fromMatch=[regex]::Match($FromVersion,('^4[.](?<minor>2|3)[.]'+$code+'(?<patch>00|01|02)$'))
  if(-not$published410F200-and-not$fromMatch.Success){throw '[mir42-upgrade-fixture-predecessor]'}
  $fromMinor=if($fromMatch.Success){[int]$fromMatch.Groups['minor'].Value}else{1}
  $fromPatch=if($fromMatch.Success){[int]$fromMatch.Groups['patch'].Value}else{0}
  if(-not$published410F200-and(($source.Minor-eq2-and($fromMinor-ne2-or$fromPatch-ge$sourcePatch)) -or
     ($source.Minor-eq3-and($fromMinor-ne2-or$fromPatch-gt2)))){throw '[mir42-upgrade-fixture-predecessor]'}
  if($HistoricalSettingsOracle-and($Target-cne'f210'-or$SourceVersion-cne'4.2.3'-or$FromVersion-cne'4.2.21000'-or-not$SpaceAge-or$SpaceIsFake)){
    throw '[mir423-f210-settings-oracle-transition]'
  }
  $direct420To422=$SourceVersion-ceq'4.2.2'-and$fromPatch-eq0
  $fixtureVersion=if($published410F200){'0.1.49'}elseif($source.Minor-eq3){'0.1.'+(40+3*$sourcePatch+$fromPatch)}elseif($SourceVersion-ceq'4.2.3'){'0.1.'+(30+$fromPatch)}elseif($direct420To422){if($SpaceIsFake){'0.1.7'}elseif($SpaceAge){'0.1.17'}else{'0.1.6'}}elseif($SpaceIsFake){if($SourceVersion-ceq'4.2.2'){'0.1.3'}else{'0.1.0'}}elseif($SpaceAge){if($SourceVersion-ceq'4.2.2'){'0.1.16'}else{'0.1.4'}}elseif($SourceVersion-ceq'4.2.2'){'0.1.2'}else{'0.1.1'}
  if($HistoricalSettingsOracle){$fixtureVersion='0.1.33'}
  if($Target-ceq'f210'-and$SourceVersion-ceq'4.2.2'-and-not$SpaceAge){
    $fixtureVersion=if($direct420To422){if($SpaceIsFake){'0.1.20'}else{'0.1.18'}}else{if($SpaceIsFake){'0.1.21'}else{'0.1.19'}}
  }
  if($Target-ceq'f200'-and$SourceVersion-ceq'4.2.2'-and-not$SpaceIsFake){
    $fixtureVersion=if($direct420To422){'0.1.26'}else{'0.1.27'}
  }
  if($Target-cin@('f110','f100')-and$SourceVersion-ceq'4.2.2'){
    $fixtureVersion=if($direct420To422){'0.1.28'}else{'0.1.29'}
  }
  $directory=Resolve-MIR441RecoveryScratchPath -Path $FixtureDirectory
  $path=Join-Path $directory 'info.json'
  Assert-MIRLibraryPath $path
  $info=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -DateKind String
  $line=switch($Target){f210{'2.1'};f200{'2.0'};f110{'1.1'};f100{'1.0'}}
  if($info.name-cne"mir-fixture-assert-upgrade-4-0-${code}00-to-4-1-${code}00"-or
    $info.factorio_version-cne$line-or$info.version-cnotin@('0.1.0',$fixtureVersion)){
    throw '[mir421-modern-base-fixture-template]'
  }
  if($info.version-ceq$fixtureVersion){return}
  $info.version=$fixtureVersion
  [IO.File]::WriteAllText($path,($info|ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false))
}

function Set-MIR423F210HistoricalSettingDefaultOracle {
  param([Parameter(Mandatory)][string]$FixtureDirectory,
    [Parameter(Mandatory)][string]$FromVersion,[Parameter(Mandatory)][string]$ToVersion)
  # The shared fixture already contains the reviewed 18-family by seven-default
  # allowance introduced in published 4.2.1 and retained in 4.2.2.  This
  # changes only the private CCC00 -> CCC03 copy's guard; all existing settings
  # and every other added setting continue through the exact-equality oracle.
  if($FromVersion-cne'4.2.21000'){throw '[mir423-f210-settings-oracle-predecessor]'}
  if($ToVersion-cne'4.2.21003'){throw '[mir423-f210-settings-oracle-version]'}
  $directory=Resolve-MIR441RecoveryScratchPath -Path $FixtureDirectory
  $path=Join-Path $directory 'control.lua'
  Assert-MIRLibraryPath $path
  $text=Get-Content -LiteralPath $path -Raw
  $old='if to_version == "4.2.21002" then'
  $new='if from_version == "4.2.21000" and to_version == "4.2.21003" then'
  $required=@(
    'local added_422_setting_defaults = {}',
    'local families = {"glycerol", "hydrochloric_acid", "hydrofluoric_acid", "nitric_acid",',
    'local defaults = {enable=true, ["effect-per-level"]=2, ["max-level"]=0,',
    '    ["research-time"]=30, ["cost-base"]=200, ["cost-growth"]=2, ["cost-linear-increment"]=0}',
    'if expected.settings[name] == nil and not equal_state(added_422_setting_defaults[name], value) then'
  )
  if(@($required|Where-Object {-not$text.Contains($_)}).Count-ne0-or[regex]::Matches($text,[regex]::Escape($old)).Count-ne1){
    throw '[mir423-f210-settings-oracle-anchor]'
  }
  [IO.File]::WriteAllText($path,$text.Replace($old,$new),[Text.UTF8Encoding]::new($false))
}

function Set-MIR423F210InheritedPromethiumDefinitionDelta {
  param([Parameter(Mandatory)][string]$FixtureDirectory,
    [Parameter(Mandatory)][string]$FromVersion,[Parameter(Mandatory)][string]$ToVersion)
  # This only changes the disposable CCC03 fixture produced by the existing
  # per-predecessor construction. Published fixture bytes retain their custody.
  if($FromVersion-cne'4.2.21001'){throw '[mir423-f210-oracle-predecessor]'}
  if($ToVersion-cne'4.2.21003'){throw '[mir423-f210-oracle-version]'}
  $directory=Resolve-MIR441RecoveryScratchPath -Path $FixtureDirectory
  $path=Join-Path $directory 'control.lua'
  Assert-MIRLibraryPath $path
  $text=Get-Content -LiteralPath $path -Raw
  $old='if (from_version ~= "4.2.21001" and not persisted_damage_probe) or to_version ~= "4.2.21002" then return false end'
  $new='if from_version ~= "4.2.21001" or to_version ~= "4.2.21003" then return false end'
  if([regex]::Matches($text,[regex]::Escape($old)).Count-ne1){throw '[mir423-f210-oracle-anchor]'}
  [IO.File]::WriteAllText($path,$text.Replace($old,$new),[Text.UTF8Encoding]::new($false))
}

function Set-MIR422F200CompleteStateUpgradeOracle {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$FixtureDirectory,
    [Parameter(Mandatory)][string]$FromVersion,
    [Parameter(Mandatory)][string]$ToVersion)
  $toMatch=[regex]::Match($ToVersion,'^4[.]2[.]200(?<patch>02|03)$')
  $fromMatch=[regex]::Match($FromVersion,'^4[.]2[.]200(?<patch>00|01|02)$')
  $legacyTransition=$toMatch.Success-and$fromMatch.Success-and([int]$fromMatch.Groups['patch'].Value-lt[int]$toMatch.Groups['patch'].Value)
  $crossMinorTransition=[regex]::IsMatch($ToVersion,'^4[.]3[.]200(?:00|01)$')-and[regex]::IsMatch($FromVersion,'^4[.]2[.]200(?:00|01|02)$')
  $published410Transition=$ToVersion-ceq'4.3.20000'-and$FromVersion-ceq'4.1.20000'
  if(-not($legacyTransition-or$crossMinorTransition-or$published410Transition)){throw '[mir422-f200-complete-oracle-transition]'}
  # Reuse the complete canonical oracle. Only its private native test copy is
  # adapted to F200 base research; Space Age-only expected rows do not exist in
  # that environment. Every observed technology, recipe and force still compares.
  $control=Get-Content -LiteralPath (Join-Path $RepoRoot 'fixtures/assert-upgrade-4-0-21000-to-4-1-21000/control.lua') -Raw
  $start='local complete_catalogue_upgrade = archetype == "space-age-native-owner"'
  $end='  and to_version:match("^4%.2%.210%d%d$")'
  $first=$control.IndexOf($start);$last=$control.IndexOf($end)
  if($first-lt0-or$last-lt$first){throw '[mir422-f200-complete-oracle-anchor]'}
  $control=$control.Remove($first,$last+$end.Length-$first).Insert($first,'local complete_catalogue_upgrade = true')
  $rows='  for _, name in ipairs({"recipe-prod-research_cargo_bay_unloading_distance-1", "recipe-prod-research_ice-1", "recipe-prod-research_science_pack_productivity-1"}) do'
  if(-not$control.Contains($rows)){throw '[mir422-f200-complete-oracle-reported-rows]'}
  $control=$control.Replace($rows,'  for _, name in ipairs({}) do')
  $control=$control.Replace('"4.0.21000"','"'+$FromVersion+'"').Replace('"4.1.21000"','"'+$ToVersion+'"')
  $control=$control.Replace('["base-default"]={technology="recipe-prod-research_iron-1",level=3}',
    '["base-default"]={technology="mining-productivity-4",level=5}')
  $control=$control.Replace('if to_version == "4.2.21002" then','if to_version == "'+$ToVersion+'" then')
  $control=$control.Replace('complete Space Age state retained','complete research state retained')
  $control=$control.Replace('mir-4121000-upgraded',('mir-'+$ToVersion.Replace('.','')+'-upgraded'))
  if($ToVersion -match '^4[.]3[.]200(?:00|01)$') {
    # Only the newly introduced, preservation-capable selector is admitted.
    # Source snapshots stay unchanged; all old settings and all research
    # definitions/investment still pass through the complete equality oracle.
    $settingAnchor='local added_422_setting_defaults = {}'
    if(-not $control.Contains($settingAnchor)){throw '[mir430-full-upgrade-setting-anchor]'}
    $control=$control.Replace($settingAnchor,'local added_422_setting_defaults = {["mir-compiler-profile"] = "full"}')
  }
  if($ToVersion -match '^4[.]2[.]') {
  $reviewed=@'
local reviewed_420_frontier = require("mir422_reviewed_science_delta")
local function reviewed_frontier_delta(name, before, after)
  if from_version ~= "4.2.20000" or to_version ~= "__MIR_F200_TO_VERSION__" then return false end
  local row = reviewed_420_frontier[name]
  if not row or not equal_state(before.prerequisites, row.before.prerequisites)
    or not equal_state(before.ingredients, row.before.ingredients) then return false end
  local expected = scalar_copy(before)
  expected.prerequisites, expected.ingredients = row.after.prerequisites, row.after.ingredients
  return equal_state(expected, after)
end

'@
  $reviewed=$reviewed.Replace('__MIR_F200_TO_VERSION__',$ToVersion)
  $control=$control.Replace('local function restored_promethium_frontier',($reviewed+"`n"+'local function restored_promethium_frontier'))
  $control=$control.Replace('and not restored_promethium_frontier(name, before.prototype, observed.technologies[name].prototype)',
    'and not reviewed_frontier_delta(name, before.prototype, observed.technologies[name].prototype)')
  }
  [IO.File]::WriteAllText((Join-Path $FixtureDirectory 'control.lua'),$control,[Text.UTF8Encoding]::new($false))
}

function Assert-MIR430Published410F200FullUpgradeTransition {
  param(
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$SourceVersion,
    [Parameter(Mandatory)][string]$FromVersion,
    [Parameter(Mandatory)][string]$ToVersion,
    [Parameter(Mandatory)][string]$FixtureName,
    [Parameter(Mandatory)][string]$Archetype,
    [bool]$SpaceIsFake,
    [ValidateSet('Full','Classic')][string]$UpgradePolicy='Full'
  )
  if($Target-cne'f200'-or$SourceVersion-cne'4.3.0'-or$FromVersion-cne'4.1.20000'-or$ToVersion-cne'4.3.20000'-or
    $FixtureName-cne'assert-upgrade-4-0-20000-to-4-1-20000'-or$Archetype-cne'base-default'-or$SpaceIsFake){
    throw '[mir430-published410-upgrade-transition]'
  }
  if($UpgradePolicy-cne'Full'){throw '[mir430-published410-upgrade-profile]'}
}

function Read-MIR430Published410F200ReleaseInput {
  param(
    [Parameter(Mandatory)]$ReleaseMetadata,
    [Parameter(Mandatory)][string]$ReleaseManifestPath,
    [Parameter(Mandatory)][string]$ArchivePath
  )
  $expectedReleaseId=383203807
  $expectedTag='v4.1.0'
  $expectedCommit='3562377b520cccb071b97b3968946eae7024c950'
  $expectedTree='e094f72aa59ecb994f12bb33c399022f20e94165'
  $expectedManifestName='mir-4.1.0.release.json'
  $expectedManifestAssetId=545663306
  $expectedManifestSha='3A79B5291E1969058C12DBDD5A599FBFFB90F1C4CCFC5E4428453929E0A7365D'
  $expectedManifestBytes=2847
  $expectedArchiveName='more-infinite-research_4.1.20000.zip'
  $expectedArchiveAssetId=545663038
  $expectedArchiveSha='7E4EEB5D0E42152F7416CAA0BCA6274A4FDDA242AFBEDAFBAD8788CEDA2ECF34'
  $expectedArchiveBytes=1059713
  if(-not(Test-Path -LiteralPath $ArchivePath -PathType Leaf) -or
    (Split-Path -Leaf $ArchivePath)-cne$expectedArchiveName-or
    (Get-Item -LiteralPath $ArchivePath).Length-ne$expectedArchiveBytes-or
    (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash-cne$expectedArchiveSha){
    throw '[mir430-published410-archive]'
  }
  if([int64]$ReleaseMetadata.id-ne$expectedReleaseId-or[string]$ReleaseMetadata.tag_name-cne$expectedTag-or
    [string]$ReleaseMetadata.target_commitish-cne$expectedCommit){throw '[mir430-published410-release-metadata]'}
  $manifestAssets=@($ReleaseMetadata.assets|Where-Object {[string]$_.name-ceq$expectedManifestName})
  $archiveAssets=@($ReleaseMetadata.assets|Where-Object {[string]$_.name-ceq$expectedArchiveName})
  if($manifestAssets.Count-ne1-or[long]$manifestAssets[0].id-ne$expectedManifestAssetId-or[long]$manifestAssets[0].size-ne$expectedManifestBytes-or
    [string]$manifestAssets[0].digest-cne('sha256:'+$expectedManifestSha.ToLowerInvariant())-or
    $archiveAssets.Count-ne1-or[long]$archiveAssets[0].id-ne$expectedArchiveAssetId-or[long]$archiveAssets[0].size-ne$expectedArchiveBytes-or
    [string]$archiveAssets[0].digest-cne('sha256:'+$expectedArchiveSha.ToLowerInvariant())){
    throw '[mir430-published410-release-asset]'
  }
  if(-not(Test-Path -LiteralPath $ReleaseManifestPath -PathType Leaf)-or
    (Get-Item -LiteralPath $ReleaseManifestPath).Length-ne$expectedManifestBytes-or
    (Get-FileHash -LiteralPath $ReleaseManifestPath -Algorithm SHA256).Hash-cne$expectedManifestSha){
    throw '[mir430-published410-release-manifest]'
  }
  try{$manifest=Get-Content -LiteralPath $ReleaseManifestPath -Raw|ConvertFrom-Json -Depth 100 -DateKind String}catch{throw '[mir430-published410-release-manifest]'}
  if([int]$manifest.schema-ne1-or[string]$manifest.kind-cne'MIR441ReleaseManifestV1'-or[string]$manifest.status-cne'technically-qualified-unpublished'-or
    [string]$manifest.title-cne'MIR 4.1.0'-or[string]$manifest.tag-cne$expectedTag-or[string]$manifest.source.commit-cne$expectedCommit-or
    [string]$manifest.source.tree-cne$expectedTree-or[string]$manifest.manifest_asset.path-cne$expectedManifestName){
    throw '[mir430-published410-release-manifest]'
  }
  $manifestArchive=@($manifest.github_assets|Where-Object {[string]$_.path-ceq('assets/'+$expectedArchiveName)})
  if($manifestArchive.Count-ne1-or[string]$manifestArchive[0].sha256-cne$expectedArchiveSha-or[long]$manifestArchive[0].bytes-ne$expectedArchiveBytes){
    throw '[mir430-published410-release-manifest]'
  }
  return [pscustomobject][ordered]@{
    kind='MIR430Published410PredecessorV1';release_id=$expectedReleaseId;source_tag=$expectedTag
    source=[ordered]@{commit=$expectedCommit;tree=$expectedTree}
    manifest=[ordered]@{path=$ReleaseManifestPath;asset_id=$expectedManifestAssetId;sha256=$expectedManifestSha;bytes=$expectedManifestBytes}
    targets=@([pscustomobject][ordered]@{target='f200';version='4.1.20000';path=$ArchivePath;sha256=$expectedArchiveSha;bytes=$expectedArchiveBytes;github_asset_id=$expectedArchiveAssetId})
  }
}

function Set-MIR42HistoricalMaintenanceUpgradeFixtureIdentity {
  param([Parameter(Mandatory)][string]$FixtureDirectory,
    [Parameter(Mandatory)][ValidateSet('f017','f016','f015','f014','f013')][string]$Target,
    [Parameter(Mandatory)][ValidateSet('4.2.1','4.2.2','4.2.3','4.3.0','4.3.1')][string]$SourceVersion,
    [AllowEmptyString()][string]$FromVersion='')
  $code=$Target.Substring(1)
  $source=[version]$SourceVersion
  $sourcePatch=$source.Build
  if([string]::IsNullOrWhiteSpace($FromVersion)){
    $FromVersion=if($source.Minor-eq3){'4.2.'+$code+'02'}else{'4.2.'+$code+($sourcePatch-1).ToString('00')}
  }
  $fromMatch=[regex]::Match($FromVersion,('^4[.](?<minor>2|3)[.]'+$code+'(?<patch>00|01|02)$'))
  if(-not$fromMatch.Success){throw '[mir42-upgrade-fixture-predecessor]'}
  $fromMinor=[int]$fromMatch.Groups['minor'].Value
  $fromPatch=[int]$fromMatch.Groups['patch'].Value
  if(($source.Minor-eq2-and($fromMinor-ne2-or$fromPatch-ge$sourcePatch)) -or
     ($source.Minor-eq3-and($fromMinor-ne2-or$fromPatch-gt2))){throw '[mir42-upgrade-fixture-predecessor]'}
  $directory=Resolve-MIR441RecoveryScratchPath -Path $FixtureDirectory
  $path=Join-Path $directory 'info.json'
  Assert-MIRLibraryPath $path
  $info=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -DateKind String
  $fixtureVersion=if($source.Minor-eq3){'1.0.'+(20+3*$sourcePatch+$fromPatch)}elseif($SourceVersion-ceq'4.2.3'){'1.0.'+(8+$fromPatch)}elseif($SourceVersion-ceq'4.2.2'){if($fromPatch-eq0){'1.0.6'}else{'1.0.7'}}else{'1.0.'+$sourcePatch}
  $line='0.'+[int]$Target.Substring(1)
  if($info.name-cne'mir-fixture-assert-upgrade-historical-terminal-to-mir42'-or
    $info.factorio_version-cne$line-or$info.version-cnotin@('1.0.0',$fixtureVersion)){
    throw '[mir42-historical-maintenance-fixture-template]'
  }
  if($info.version-ceq$fixtureVersion){return}
  $info.version=$fixtureVersion
  [IO.File]::WriteAllText($path,($info|ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false))
}

function Set-MIR422HistoricalCompleteStateUpgradeOracle {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$FixtureDirectory,
    [Parameter(Mandatory)][ValidateSet('f110','f100','f017','f016','f015','f014','f013')][string]$Target,
    [Parameter(Mandatory)][string]$FromVersion,[Parameter(Mandatory)][string]$ToVersion)
  $line=switch($Target){f110{'1.1'};f100{'1.0'};default{'0.'+[int]$Target.Substring(1)}}
  $path=Join-Path $FixtureDirectory 'control.lua'
  $text=Get-Content -LiteralPath $path -Raw
  $prefix='local complete_state_oracle = require("mir422_complete_state").new("'+$line+'", "'+$FromVersion+'", "'+$ToVersion+'")'+"`n"
  if($Target-cin@('f110','f100')){
    $source='  log("[mir-fixture] " .. from_version .. " upgrade source proof complete archetype=" .. archetype)'
    $upgrade='  state.upgrade_complete = true'
    $tick='script.on_event(defines.events.on_tick, function()'
    $reload='    log("[mir-fixture] " .. to_version .. " upgraded save reload proof complete archetype=" .. archetype)'
    foreach($anchor in @($source,$upgrade,$tick,$reload)){if(-not$text.Contains($anchor)){throw '[mir422-historical-complete-oracle-anchor]'}}
    $text=$text.Replace($source,('  complete_state_oracle.capture()'+"`n"+$source))
    $text=$text.Replace($upgrade,('  complete_state_oracle.verify("upgrade")'+"`n"+$upgrade))
    $text=$text.Replace($reload,'    verify_complete_state_after_load = true')
    $text=$text.Replace($tick,($tick+"`n"+'  if verify_complete_state_after_load then'+"`n"+'    complete_state_oracle.verify("reload")'+"`n"+$reload+"`n"+'    verify_complete_state_after_load = false'+"`n"+'  end'))
    $prefix+='local verify_complete_state_after_load = false'+"`n"
  }else{
    $source='  seed_source_state()'
    $check='local function assert_retained_state(phase)'
    foreach($anchor in @($source,$check)){if(-not$text.Contains($anchor)){throw '[mir422-historical-complete-oracle-anchor]'}}
    $text=$text.Replace($source,($source+"`n"+'  complete_state_oracle.capture()'))
    $text=$text.Replace($check,($check+"`n"+'  complete_state_oracle.verify(phase == "reload" and "reload" or "upgrade")'))
  }
  Copy-Item -LiteralPath (Join-Path $RepoRoot 'tests/support/MIR422HistoricalCompleteState.lua') -Destination (Join-Path $FixtureDirectory 'mir422_complete_state.lua')
  [IO.File]::WriteAllText($path,($prefix+$text),[Text.UTF8Encoding]::new($false))
}

function Set-MIR430FullCompilerProfileUpgradeAllowance {
  param(
    [Parameter(Mandatory)][ValidateSet('f210','f110','f100')][string]$Target,
    [Parameter(Mandatory)][string]$FixtureDirectory,
    [Parameter(Mandatory)][string]$FromVersion,
    [Parameter(Mandatory)][string]$ToVersion
  )
  $code=$Target.Substring(1)
  if($FromVersion-cnotin@("4.2.${code}00","4.2.${code}01","4.2.${code}02")-or$ToVersion-cnotin@("4.3.${code}00","4.3.${code}01")){
    throw '[mir430-full-upgrade-setting-transition]'
  }
  $directory=Resolve-MIR441RecoveryScratchPath -Path $FixtureDirectory
  if($Target-ceq'f210'){
    $path=Join-Path $directory 'control.lua';Assert-MIRLibraryPath $path
    $text=Get-Content -LiteralPath $path -Raw
    $anchor='local added_422_setting_defaults = {}'
    $completeStateGate='  and to_version:match("^4%.2%.210%d%d$")'
    $completeStateHooks=@('    export_state("source")','    export_state("upgrade")','      export_state("reload")')
    if([regex]::Matches($text,[regex]::Escape($anchor)).Count-ne1){throw '[mir430-full-upgrade-setting-anchor]'}
    if([regex]::Matches($text,[regex]::Escape($completeStateGate)).Count-ne1-or
       @($completeStateHooks|Where-Object {-not$text.Contains($_)}).Count){
      throw '[mir430-full-upgrade-complete-state-anchor]'
    }
    $text=$text.Replace($anchor,'local added_422_setting_defaults = {["mir-compiler-profile"] = "full"}')
    # The same Full fixture that authorizes the newly added selector must retain
    # the complete-state path on the exact cross-minor F210 destination. The
    # source, upgrade and reload hooks above remain mandatory and are checked
    # before this private fixture transformation.
    $text=$text.Replace($completeStateGate,('  and (to_version:match("^4%.2%.210%d%d$") or to_version == "'+$ToVersion+'")'))
    [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
    return
  }
  $path=Join-Path $directory 'mir422_complete_state.lua';Assert-MIRLibraryPath $path
  $text=Get-Content -LiteralPath $path -Raw
  $anchor="        for _, field in ipairs({`"effects`", `"settings`", `"queue`", `"research_queue_enabled`", `"current_research`", `"research_progress`"}) do`n          if not equal(before[field], after[field]) then fail(`"saved force state changed: `" .. force_name .. `"/`" .. field) end`n        end"
  $replacement="        for _, field in ipairs({`"effects`", `"settings`", `"queue`", `"research_queue_enabled`", `"current_research`", `"research_progress`"}) do`n          local retained = equal(before[field], after[field])`n          if field == `"settings`" and before[field][`"mir-compiler-profile`"] == nil and after[field][`"mir-compiler-profile`"] == `"full`" then`n            local expected_settings = copy(before[field])`n            expected_settings[`"mir-compiler-profile`"] = `"full`"`n            retained = equal(expected_settings, after[field])`n          end`n          if not retained then fail(`"saved force state changed: `" .. force_name .. `"/`" .. field) end`n        end"
  if([regex]::Matches($text,[regex]::Escape($anchor)).Count-ne1){throw '[mir430-full-upgrade-setting-anchor]'}
  [IO.File]::WriteAllText($path,$text.Replace($anchor,$replacement),[Text.UTF8Encoding]::new($false))
}

function Get-MIR421SpaceFakeUpgradeDescriptor {
  param([string]$Target,[string]$FromVersion,[string]$ToVersion,[string]$FixtureName,[string]$Archetype,
    [ValidateSet('4.2.1','4.2.2')][string]$SourceVersion='4.2.1')
  $code = switch -CaseSensitive ($Target) { 'f210' { '210' }; 'f200' { '200' }; default { throw '[mir421-sif-target]' } }
  $expectedFixture = "assert-upgrade-4-0-${code}00-to-4-1-${code}00"
  $expectedArchetype = if ($Target -ceq 'f210') { 'base-continuations' } else { 'base-default' }
  $patch=([version]$SourceVersion).Build
  $fromPatches=if($SourceVersion-ceq'4.2.2'){@(0,1)}else{@(0)}
  $allowedFrom=@($fromPatches|ForEach-Object {'4.2.'+$code+$_.ToString('00')})
  if ($FromVersion -cnotin $allowedFrom -or $ToVersion -cne ('4.2.'+$code+$patch.ToString('00')) -or
      $FixtureName -cne $expectedFixture -or $Archetype -cne $expectedArchetype) { throw '[mir421-sif-transition]' }
  $predecessorSourceVersion='4.2.'+[int]$FromVersion.Substring($FromVersion.Length-2)
  $line = if ($Target -ceq 'f210') { '2.1' } else { '2.0' }
  $inputs = if ($Target -ceq 'f210') { @(
    # 1.0.76 fails native 2.1.21 item validation before save creation; 1.0.78
    # carries the upstream fuel-categories correction and requires commons .33.
    [pscustomobject]@{name='space-is-fake';version='1.0.78';sha256='3B5F2A381ADF1D9AECF048293E20035963A528720FBDC148CCC2B0418049FF13'},
    [pscustomobject]@{name='cr-commons';version='1.0.33';sha256='378D3114B09C872358088B33500BC4AB0B9B9EFD9E5650DBEA0E87B5914C29BB'}
  ) } else { @(
    [pscustomobject]@{name='space-is-fake';version='1.0.60';sha256='860F2048A7E6F4C2ECD1A9CECA6ECDD340ECF797773EC582A6E60FFE6F8D87AC'},
    [pscustomobject]@{name='cr-commons';version='1.0.27';sha256='6F3622AE6270F9B365A9E2E07FA5E07B61B2BBFCAB3A4D930CC410EBDEB63B92'}
  ) }
  return [pscustomobject]@{request='SIF-01';line=$line;target=$Target;inputs=$inputs;mod_names=@($inputs | ForEach-Object name);
    source_version=$SourceVersion;predecessor_source_version=$predecessorSourceVersion;scenario="SIF-01-published-$predecessorSourceVersion-to-$SourceVersion"}
}

function Resolve-MIR421SpaceFakeUpgradeInputs {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Descriptor,[string[]]$LocalModLibraryDirs=@())
  # The dependency library is a read-only input. No downloads or copy fallback.
  if ($LocalModLibraryDirs.Count -eq 0) { throw '[mir-upgrade-library-required] Supply the selected machine-local archive library explicitly.' }
  $expected=[ordered]@{}
  foreach ($row in $Descriptor.inputs) { $expected[([string]$row.name+'_'+[string]$row.version+'.zip')]=[string]$row.sha256 }
  $resolved=Resolve-MIRNativeProbeDependencyInputs -StageRoot (Join-Path $RepoRoot ('build/tmp/mir421-sif-input-lookup-'+$Descriptor.target)) -ExpectedArchives $expected -LocalModLibraryDirs $LocalModLibraryDirs
  return @(foreach ($row in $Descriptor.inputs) {
    $fileName = [string]$row.name + '_' + [string]$row.version + '.zip'
    $path = $resolved[$fileName].source_path
    [pscustomobject]@{source_path=$path;file_name=$fileName;expected_sha256=[string]$row.sha256;immutable=$true;role='native-sif-dependency';identity=[ordered]@{name=$row.name;version=$row.version;factorio_line=$Descriptor.line};provenance=[ordered]@{kind='verified-canonical-local-library';request='SIF-01'}}
  })
}

function Get-MIRUpgradeLibrarySelection {
  param([Parameter(Mandatory)][string]$Library,[Parameter(Mandatory)][string]$EngineDataDirectory,
    [Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$ExpectedSha256,[object[]]$Dependencies=@(),
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$FixtureDirectories,[bool]$EnableDlc=$false)
  $inventory=@(Get-MIRLibraryInventory -LibraryDirectory $Library -EngineDataDirectory $EngineDataDirectory)
  $rows=[Collections.Generic.List[object]]::new();$hashes=[ordered]@{}
  $builtins=@('base')
  if($EnableDlc){$builtins+=@('elevated-rails','quality','space-age')}
  if($EnableDlc-and@($inventory|Where-Object {$_.builtin-and$_.name-ceq'recycler'}).Count){$builtins+='recycler'}
  foreach($name in $builtins){
    $matches=@($inventory|Where-Object {$_.builtin-and$_.name-ceq$name})
    if($matches.Count-ne1){throw "[mir-upgrade-builtin-missing] $name"}
    $rows.Add([ordered]@{name=$name;version=$matches[0].version;enabled=$true})
  }
  $candidate=[ordered]@{file_name=[IO.Path]::GetFileName($Archive);expected_sha256=$ExpectedSha256;identity=@{name='more-infinite-research';version=$Version}}
  foreach($inputRow in @($Dependencies)+@($candidate)){
    $path=Join-Path $Library $inputRow.file_name
    $matches=@($inventory|Where-Object {-not$_.builtin-and$_.name-ceq$inputRow.identity.name-and$_.version-ceq$inputRow.identity.version})
    if($matches.Count-ne1-or$matches[0].path-cne$path){throw "[mir-upgrade-library-input-missing] $($inputRow.file_name)"}
    if((Get-MIRImmutableInputSha256 $path)-cne$inputRow.expected_sha256){throw "[mir-upgrade-library-input-hash] $($inputRow.file_name)"}
    $rows.Add([ordered]@{name=$matches[0].name;version=$matches[0].version;enabled=$true})
    $hashes[$inputRow.file_name]=[string]$inputRow.expected_sha256
  }
  foreach($directory in $FixtureDirectories){
    $info=Get-Content -LiteralPath (Join-Path $directory 'info.json') -Raw|ConvertFrom-Json
    $name=$info.name+'_'+$info.version+'.zip';$path=Join-Path $Library $name
    Assert-MIRLibraryFixtureArchive -Archive $path -SourceDirectory $directory
    $rows.Add([ordered]@{name=$info.name;version=$info.version;enabled=$true})
    $hashes[$name]=Get-MIRImmutableInputSha256 $path
  }
  if(@($rows|Group-Object {$_.name}|Where-Object Count -GT 1).Count){throw '[mir-upgrade-library-duplicate-name]'}
  return [pscustomobject]@{mod_list=[ordered]@{mods=@($rows)};archive_hashes=$hashes}
}

function Get-MIRUpgradeLinkedArchiveBytes {
  param([Parameter(Mandatory)]$Lease)
  [int64]$bytes = 0
  if (-not $Lease.record.require_hard_links) { throw '[mir421-sif-dependency-lease]' }
  if ($Lease.closed) { $null=Assert-MIRImmutableInputTerminalReceipt -Receipt $Lease.record }
  foreach ($input in $Lease.record.inputs) {
    if ($input.staging_mode -cne 'hardlink' -or
        (Get-MIRImmutableInputFileIdentity -Path $input.source_path) -cne (Get-MIRImmutableInputFileIdentity -Path $input.stage_path)) { throw '[mir421-sif-dependency-alias]' }
    $bytes += [int64](Get-Item -LiteralPath $input.stage_path).Length
  }
  return $bytes
}

function New-MIRUpgradeLinkedProfile {
  param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Dependencies,
    [Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$ExpectedSha256,
    [Parameter(Mandatory)][string]$Version,[ValidateSet('source','candidate')][string]$Role,[string]$Request='native-upgrade')
  $input=[ordered]@{source_path=$Archive;file_name=[IO.Path]::GetFileName($Archive);expected_sha256=$ExpectedSha256;
    immutable=$true;role=$Role;identity=[ordered]@{name='more-infinite-research';version=$Version};
    provenance=[ordered]@{kind='verified-upgrade-archive-input';request=$Request}}
  New-Item -ItemType Directory -Path $RunRoot -ErrorAction Stop | Out-Null
  return New-MIRImmutableInputLease -RunRoot $RunRoot -StageDirectory (Join-Path $RunRoot 'mods') -Inputs @($Dependencies+$input) -RequireHardLinks
}

function Move-MIRUpgradeProfileState {
  param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$SourceMods,
    [Parameter(Mandatory)][string]$TargetMods,[Parameter(Mandatory)][string]$FixtureName)
  if ($FixtureName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw '[mir421-sif-fixture-move-boundary]' }
  $moves=@()
  foreach ($name in @($FixtureName,'mod-settings.dat')) {
    $source=Join-Path $SourceMods $name
    $target=Join-Path $TargetMods $name
    foreach ($path in @($source,$target)) {
      if (-not (Test-MIR441PathContained -Root $RunRoot -Path ([IO.Path]::GetFullPath($path)))) { throw '[mir421-sif-fixture-move-boundary]' }
    }
    if (-not (Test-Path -LiteralPath $source)) {
      if ($name -ceq $FixtureName) { throw '[mir421-sif-fixture-missing]' }
      continue
    }
    if (Test-Path -LiteralPath $target) { throw '[mir421-sif-profile-state-collision]' }
    $moves += [pscustomobject]@{source=$source;target=$target}
  }
  foreach ($move in $moves) { Move-Item -LiteralPath $move.source -Destination $move.target }
}

function Assert-MIR421SpaceFakeUpgradeMarker {
  param([string]$Text,[ValidateSet('source','upgrade','reload')][string]$Stage)
  $marker=[regex]::Escape("[mir-fixture] SIF-01 native continuations verified stage=$Stage")
  if (-not [regex]::IsMatch($Text,'(^|\r?\n)[^\r\n]*'+$marker+'(\r?\n|$)')) { throw "[mir421-sif-$Stage-marker]" }
}

function Add-MIR421SpaceFakeUpgradeOracle {
  param([Parameter(Mandatory)][string]$ControlText)
  if ($ControlText.Contains('require("mir421_space_fake_upgrade")')) { throw '[mir421-sif-fixture-anchor]' }
  # This scenario always enables Space Age. Its native data updates remove
  # mining-productivity-4 and make mining-productivity-3 infinite. Keep the
  # F200 fixture's earned level and queued progress checks on that native owner.
  $baseMiningAnchor='local technology_name="mining-productivity-4"'
  if($ControlText.Contains($baseMiningAnchor)){
    if([regex]::Matches($ControlText,[regex]::Escape($baseMiningAnchor)).Count-ne1){throw '[mir421-sif-fixture-anchor]'}
    $ControlText=$ControlText.Replace($baseMiningAnchor,'local technology_name="mining-productivity-3"')
  }
  # Specialize only the disposable copy of the existing generated fixture.
  # Preserve its research/progress oracle and require each insertion anchor once.
  $anchors = @(
    @('log("[mir-fixture] "..from_version.." upgrade source proof complete archetype="..archetype)', 'sif.capture();log("[mir-fixture] "..from_version.." upgrade source proof complete archetype="..archetype)'),
    @('state.upgrade_complete=true;log', 'sif.verify("upgrade");state.upgrade_complete=true;log'),
    @('script.on_event(defines.events.on_tick,function()', 'script.on_event(defines.events.on_tick,function() if script.active_mods["more-infinite-research"] == to_version then sif.verify("reload") end;')
  )
  foreach ($pair in $anchors) {
    if ([regex]::Matches($ControlText,[regex]::Escape($pair[0])).Count -ne 1) { throw '[mir421-sif-fixture-anchor]' }
    $ControlText=$ControlText.Replace($pair[0],$pair[1])
  }
  return 'local sif = require("mir421_space_fake_upgrade")' + "`n" + $ControlText
}

function Read-MIR423F200BobAngelUpgradeProfile {
  param([Parameter(Mandatory)][string]$Path)
  $profile=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json -Depth 20
  if($profile.schema-ne1-or$profile.kind-cne'MIR423F200BobAngelObservedUpgradeProfileV1'-or
     $profile.identity-cne'f200-bob-angel-observed-2026-10-11'-or
     $profile.status-cne'acquired-and-locked-not-load-tested'-or$profile.target-cne'f200'-or
     $profile.factorio_line-cne'2.0'-or$profile.engine_version-cne'2.0.77'-or$profile.settings_mode-cne'Defaults'-or
     [string]$profile.engine_sha256-cnotmatch'^[0-9A-F]{64}$'){
    throw '[mir423-f200-bob-angel-profile]'
  }
  $lock=$profile.source_lock
  if($null-eq$lock-or$lock.path-cne'C:\Projects\Factorio\testmods\profiles\2.0\bob-angel--with-mir\lock.json'-or
     $lock.sha256-cne'00193B07816DBB0043FDDC0BC801A67BCE47041EC60C171D6837F2141CBF9FED'-or
     $lock.identity_sha256-cne'AF1B932BF627053685FEC050FF97CC71F50A682B89A64FDACA3223F81771BF22'-or
     $lock.status-cne'acquired-and-locked-not-load-tested'){
    throw '[mir423-f200-bob-angel-custody]'
  }
  $expected=[ordered]@{
    angelsbioprocessing='2.0.3';angelsbioprocessinggraphics='2.0.0';angelspetrochem='2.0.3';angelspetrochemgraphics='2.0.1';
    angelsrefining='2.0.4';angelsrefininggraphics='2.0.0';angelssmelting='2.0.5';angelssmeltinggraphics='2.0.0';
    bobelectronics='2.1.1';boblibrary='2.1.0';bobores='2.1.2';bobplates='2.1.1';bobrevamp='2.1.1'
  }
  $expectedArchives=[ordered]@{
    'angelsbioprocessing_2.0.3.zip'='766B5784C3EB7A0B43D1B2C58ABCEC47EA69E4677129DC5C9255BEB66DC86B1B';
    'angelsbioprocessinggraphics_2.0.0.zip'='8C4DCBBF61772C4276A9B655FB9173A4D3B0FCE0872D8F60FD8600225A16AB66';
    'angelspetrochem_2.0.3.zip'='DFEBBC1F4E9F13016006071CBB064FF6289EFBAF92A7290D716C0D1E8C20430D';
    'angelspetrochemgraphics_2.0.1.zip'='B8D877865D50E1157EED80CCE56F21174A69D81453075A825A837AB375CF3262';
    'angelsrefining_2.0.4.zip'='8E78BA1FE453BA90999F6FECED81F9DBF41F1EF49EEB423BA6C4CE08C1DCDC42';
    'angelsrefininggraphics_2.0.0.zip'='0B09E4335640DC580F742B04F9C109ED544F74A685C11CB1878B33DB36D7AF25';
    'angelssmelting_2.0.5.zip'='6DDF5D7BAF4BACDE0398E47BF29EF3AECE41A34F33210439AD0C60C7ADE7FBB4';
    'angelssmeltinggraphics_2.0.0.zip'='D638AA7A67405811279F96370BF5FC026CCE476048FDF16D91261354A858C6EF';
    'bobelectronics_2.1.1.zip'='BF11C8AB53F732564770DB0E7AAD24C07AF30196DA49394FA6E03E85939B38F3';
    'boblibrary_2.1.0.zip'='1CB971B7A39F0805F14DD0F27F17CC832B7FFC6608CB2234E182062FC8DBF62B';
    'bobores_2.1.2.zip'='BB0916DC28C1DD2E4A62E3F102298F7C47B5E07930FA5C84302B0879D983DF94';
    'bobplates_2.1.1.zip'='A6DBCA13C579E6E65E2A8E2D605AC97C789771F3C6E2660AA0F19AE1049FC77B';
    'bobrevamp_2.1.1.zip'='CF9AD291B6135125E29CDF452DC363101FDDAAB759DC9F713FE51DC29F1B9EEB'
  }
  $mods=@($profile.upstream_mods)
  if($mods.Count-ne$expected.Count-or@($mods|Group-Object name|Where-Object Count -GT 1).Count){throw '[mir423-f200-bob-angel-selection]'}
  if($null-eq$profile.archive_sha256-or@($profile.archive_sha256.PSObject.Properties).Count-ne$expected.Count){throw '[mir423-f200-bob-angel-archive-count]'}
  $inputs=@()
  foreach($name in $expected.Keys){
    $row=@($mods|Where-Object name -CEQ $name)
    if($row.Count-ne1-or$row[0].enabled-isnot[bool]-or-not$row[0].enabled-or$row[0].version-cne$expected[$name]){throw "[mir423-f200-bob-angel-selection] $name"}
    $filename=$name+'_'+$expected[$name]+'.zip'
    $hashProperty=$profile.archive_sha256.PSObject.Properties[$filename]
    if($null-eq$hashProperty-or[string]$hashProperty.Value-cne$expectedArchives[$filename]){throw "[mir423-f200-bob-angel-archive-hash] $filename"}
    $inputs+=,[pscustomobject]@{file_name=$filename;expected_sha256=[string]$hashProperty.Value;identity=[ordered]@{name=$name;version=$expected[$name]};role='acquired-bob-angel-upstream'}
  }
  $observer=$profile.observer
  if($null-eq$observer-or$observer.name-cne'mir423-startup-observer'-or$observer.version-cne'1.0.0'-or
     $observer.file_name-cne'mir423-startup-observer_1.0.0.zip'-or$observer.sha256-cne'9DE91C1A748B9BE9592C4A8ACBA8A35983B115A32582F200B5A5D22812AC1F23'-or
     $observer.script-cne'data-final-fixes.lua'){
    throw '[mir423-f200-bob-angel-observer]'
  }
  $inputs+=,[pscustomobject]@{file_name=[string]$observer.file_name;expected_sha256=[string]$observer.sha256;identity=[ordered]@{name=[string]$observer.name;version=[string]$observer.version};role='honest-active-mods-observer'}
  return [pscustomobject]@{profile=$profile;inputs=$inputs;observer=$observer;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
}

function Assert-MIR423F200BobAngelUpgradeTransition {
  param([string]$Target,[string]$FromVersion,[string]$ToVersion,[string]$FixtureName,[string]$Archetype,
    [bool]$SpaceIsFake,[string[]]$SourceOnlyFixtureNames=@(),[ValidateSet('4.2.1','4.2.2','4.2.3','4.3.0','4.3.1')][string]$SourceVersion='4.2.3')
  $maintenance=[bool]($SourceVersion-ceq'4.2.3'-and$FromVersion-ceq'4.2.20002'-and$ToVersion-ceq'4.2.20003')
  $full430=[bool]($SourceVersion-ceq'4.3.0'-and$FromVersion-ceq'4.2.20002'-and$ToVersion-ceq'4.3.20000')
  if($Target-cne'f200'-or-not($maintenance-or$full430)-or
     $FixtureName-cne'assert-upgrade-4-0-20000-to-4-1-20000'-or$Archetype-cne'f200-bob-angel'-or
     $SpaceIsFake-or$SourceOnlyFixtureNames.Count){
    throw '[mir423-f200-bob-angel-transition]'
  }
}

function Set-MIR423F200BobAngelCompleteStateUpgradeOracle {
  param([Parameter(Mandatory)][string]$FixtureDirectory,[Parameter(Mandatory)][string]$FromVersion,[Parameter(Mandatory)][string]$ToVersion)
  $maintenance=[bool]($FromVersion-ceq'4.2.20002'-and$ToVersion-ceq'4.2.20003')
  $full430=[bool]($FromVersion-ceq'4.2.20002'-and$ToVersion-ceq'4.3.20000')
  if(-not($maintenance-or$full430)){throw '[mir423-f200-bob-angel-oracle-transition]'}
  $directory=Resolve-MIR441RecoveryScratchPath -Path $FixtureDirectory
  $controlPath=Join-Path $directory 'control.lua';$settingsPath=Join-Path $directory 'settings.lua';$infoPath=Join-Path $directory 'info.json'
  foreach($path in @($controlPath,$settingsPath,$infoPath)){Assert-MIRLibraryPath $path}
  $control=Get-Content -LiteralPath $controlPath -Raw
  $profileAnchor='["base-default"]={technology="mining-productivity-4",level=5}'
  if([regex]::Matches($control,[regex]::Escape($profileAnchor)).Count-ne1){throw '[mir423-f200-bob-angel-oracle-anchor]'}
  $control=$control.Replace($profileAnchor,$profileAnchor+', ["f200-bob-angel"]={technology="mining-productivity-4",level=5}')
  # This is deliberately narrower than the retained generic complete-state
  # oracle. Both the 4.2 performance lane and the exact 4.3 Full lane reject
  # even an unresearched extra technology for this fixed Bob/Angel input.
  # Earlier predecessor lanes retain their reviewed feature allowances.
  $permissiveTechnologySetGuard='(?m)^  for name, after in pairs\(observed\.technologies\) do\r?\n    if not expected\.technologies\[name\] and after\.researched then fail\("new research was awarded without earning it: " \.\. name\) end\r?\n  end$'
  $technologySetGuard=[regex]::new($permissiveTechnologySetGuard)
  if($technologySetGuard.Matches($control).Count-ne1){throw '[mir423-f200-bob-angel-performance-only-anchor]'}
  $strictTechnologySetGuard=@'
  for name in pairs(observed.technologies) do
    if not expected.technologies[name] then
      fail("new technology added in performance-only upgrade: " .. name)
    end
  end
'@.TrimEnd()
  $control=$technologySetGuard.Replace($control,$strictTechnologySetGuard,1)
  [IO.File]::WriteAllText($controlPath,$control,[Text.UTF8Encoding]::new($false))
  $settings=Get-Content -LiteralPath $settingsPath -Raw
  $settingsAnchor='default_value="base-default",allowed_values={"base-default"}'
  if([regex]::Matches($settings,[regex]::Escape($settingsAnchor)).Count-ne1){throw '[mir423-f200-bob-angel-settings-anchor]'}
  $settings=$settings.Replace($settingsAnchor,'default_value="f200-bob-angel",allowed_values={"base-default","f200-bob-angel"}')
  [IO.File]::WriteAllText($settingsPath,$settings,[Text.UTF8Encoding]::new($false))
  $info=Get-Content -LiteralPath $infoPath -Raw|ConvertFrom-Json
  $expectedVersion=if($full430){'0.1.42'}else{'0.1.32'}
  $nextVersion=if($full430){'0.1.42'}else{'0.1.33'}
  if($info.version-cne$expectedVersion){throw '[mir423-f200-bob-angel-fixture-identity]'}
  $info.version=$nextVersion
  [IO.File]::WriteAllText($infoPath,($info|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
}

function Assert-MIR423F200BobAngelFullStateActiveMods {
  param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)][object[]]$ExpectedSelection,[Parameter(Mandatory)][ValidateSet('source','upgrade','reload')][string]$Stage)
  if($null-eq$Snapshot.active_mods){throw "[mir423-f200-bob-angel-active-mods] $Stage"}
  $expected=[ordered]@{}
  foreach($row in $ExpectedSelection){
    $name=[string]$row.name;$version=[string]$row.version
    if([string]::IsNullOrWhiteSpace($name)-or$version-cnotmatch'^\d+[.]\d+[.]\d+$'-or$expected.Contains($name)){throw "[mir423-f200-bob-angel-selection] $Stage"}
    $expected[$name]=$version
  }
  $actual=[ordered]@{}
  foreach($property in @($Snapshot.active_mods.PSObject.Properties)){
    $name=[string]$property.Name;$version=[string]$property.Value
    if([string]::IsNullOrWhiteSpace($name)-or$version-cnotmatch'^\d+[.]\d+[.]\d+$'-or$actual.Contains($name)){throw "[mir423-f200-bob-angel-active-mods] $Stage"}
    $actual[$name]=$version
  }
  if($actual.Count-ne$expected.Count){throw "[mir423-f200-bob-angel-active-mods] $Stage"}
  foreach($name in $expected.Keys){if(-not$actual.Contains($name)-or$actual[$name]-cne$expected[$name]){throw "[mir423-f200-bob-angel-active-mods] $Stage"}}
  return [pscustomobject]@{stage=$Stage;active_mods=@($actual.Keys|Sort-Object|ForEach-Object {[ordered]@{name=$_;version=$actual[$_]}})}
}
