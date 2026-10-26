# One governed process tree owns a loopback host and two graphical clients.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ArchiveLibrary,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$ProfilePath,
  [Parameter(Mandatory)][string[]]$FixtureSources,
  [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedMIRArchiveSha256,
  [Parameter(Mandatory)][string]$OutputRoot,
  [ValidateSet('library-multiplayer','library-paired-browser','scripted-effects-multiplayer')][string]$FixtureCase='library-multiplayer',
  # The lower value admits only the bounded functional F200/F210 Library
  # sessions.  Its F210 use is conservative admission, not a measured peak.
  # Other multiplayer fixtures retain the existing 8 GiB process-tree ceiling.
  [ValidateSet(7168,8192)][int]$SessionExpectedPeakMemoryMiB=8192,
  [switch]$CollectProcessMemoryObservations,
  # This is an environment-only stop after the fixture's real 120-tick
  # two-client predicate.  It is deliberately opt-in so the qualified Library
  # session continues to use its original profile, identities and GUI path.
  [switch]$StandaloneIdentityDiscovery,
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/DirectLibraryStartupMeasurement.ps1')
function Assert-Session([bool]$Condition,[string]$Message) {
  if(-not $Condition){throw "[mir5-multiplayer-fixture] $Message"}
}
function Assert-MultiplayerFixtureSelection {
  param(
    [Parameter(Mandatory)][System.Collections.IDictionary]$Selection,
    [Parameter(Mandatory)][string]$EngineSha256,
    [Parameter(Mandatory)][string]$FixtureCase,
    [switch]$StandaloneIdentityDiscovery
  )
  # These are the only fixed two-client selections admitted by this harness.
  # Profile kind and fixture case bind each row: F210 remains functional
  # Library-only, while F200 keeps the named paired Browser and Space Age
  # scripted closures distinct from the four-mod Library selections.
  $targets=@(
    [ordered]@{
      fixture_case='library-multiplayer';target='f200'
      kind='mir5-library-multiplayer-f200-native-selection';factorio_line='2.0';base='2.0.77'
      engine_sha256='D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B';mir='5.0.20000';build_version=84539
      observer_sha256='723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87'
      fixture_mods=@('mir-fixture-mir5-library-multiplayer@0.1.0')
      optional_archives=@('more-infinite-research_5.0.20000.zip','mir-fixture-mir5-library-multiplayer_0.1.0.zip')
    }
    [ordered]@{
      fixture_case='library-multiplayer';target='f200'
      kind='mir5-library-multiplayer-current-f200-native-selection';factorio_line='2.0';base='2.0.77'
      engine_sha256='D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B';mir='5.0.20000';build_version=84539
      observer_sha256='723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87'
      fixture_mods=@('mir-fixture-mir5-library-multiplayer@0.1.0')
      optional_archives=@('more-infinite-research_5.0.20000.zip','mir-fixture-mir5-library-multiplayer_0.1.0.zip')
    }
    [ordered]@{
      fixture_case='library-multiplayer';target='f210'
      kind='mir5-library-multiplayer-f210-native-selection';factorio_line='2.1';base='2.1.23'
      engine_sha256='FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060';mir='5.0.21000';build_version=87750
      observer_sha256='2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C'
      fixture_mods=@('mir-fixture-mir5-library-multiplayer@0.1.0')
      optional_archives=@('more-infinite-research_5.0.21000.zip','mir-fixture-mir5-library-multiplayer_0.1.0.zip')
    }
    [ordered]@{
      fixture_case='library-multiplayer';target='standalone-identity-discovery'
      kind='mir5-library-standalone-identity-discovery-f210-selection';factorio_line='2.1';base='2.1.23'
      engine_sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38';mir='5.0.21000';build_version=87750
      observer_sha256='A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0'
      mir_archive_sha256='C563CB5B96C9E64CB3373BDB60CF5C8B7D3C97E93EADB8F924443C703CDC024D'
      fixture_mods=@('mir-fixture-mir5-library-multiplayer@0.1.1')
      optional_archives=@('more-infinite-research_5.0.21000.zip','mir-fixture-mir5-library-multiplayer_0.1.1.zip')
      fixture_archive_required=$true;standalone_identity_discovery=$true
    }
    [ordered]@{
      fixture_case='library-multiplayer';target='f210'
      kind='mir5-library-api-consumers-f210-native-selection';factorio_line='2.1';base='2.1.23'
      engine_sha256='FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060';mir='5.0.21000';build_version=87750
      observer_sha256='2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C'
      mir_archive_sha256='428A789CA03828D2F7F93EC65C49FD3157FD6D547CC569DDA2C0129D6504647A'
      fixture_mods=@('mir-fixture-mir5-library-multiplayer@0.1.0','mir-fixture-mir5-api-alpha@0.1.0','mir-fixture-mir5-api-beta@0.1.0')
      optional_archives=@('more-infinite-research_5.0.21000.zip','mir-fixture-mir5-library-multiplayer_0.1.0.zip','mir-fixture-mir5-api-alpha_0.1.0.zip','mir-fixture-mir5-api-beta_0.1.0.zip')
      api_client_consumers=$true
    }
    [ordered]@{
      fixture_case='library-paired-browser';target='f200'
      kind='mir5-library-paired-browser-f200-native-selection';factorio_line='2.0';base='2.0.77'
      engine_sha256='D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B';mir='4.7.20002';build_version=84539
      observer_sha256='723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87'
      fixture_mods=@('mir-fixture-mir5-library-paired-browser@0.1.0','mir-fixture-mir5-library-paired-browser-arm-published@0.1.0')
      optional_archives=@('more-infinite-research_4.7.20002.zip','mir-fixture-mir5-library-paired-browser_0.1.0.zip','mir-fixture-mir5-library-paired-browser-arm-published_0.1.0.zip')
    }
    [ordered]@{
      fixture_case='library-paired-browser';target='f200'
      kind='mir5-library-paired-browser-f200-native-selection';factorio_line='2.0';base='2.0.77'
      engine_sha256='D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B';mir='5.0.20000';build_version=84539
      observer_sha256='723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87'
      fixture_mods=@('mir-fixture-mir5-library-paired-browser@0.1.0','mir-fixture-mir5-library-paired-browser-arm-mir5@0.1.0')
      optional_archives=@('more-infinite-research_5.0.20000.zip','mir-fixture-mir5-library-paired-browser_0.1.0.zip','mir-fixture-mir5-library-paired-browser-arm-mir5_0.1.0.zip')
    }
    [ordered]@{
      fixture_case='scripted-effects-multiplayer';target='f200'
      kind='mir5-scripted-effects-multiplayer-f200-space-age-native-selection';factorio_line='2.0';base='2.0.77'
      engine_sha256='D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B';mir='5.0.20000';build_version=84539
      observer_sha256='723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87'
      fixture_mods=@('elevated-rails@2.0.77','quality@2.0.77','space-age@2.0.77','mir-fixture-mir5-scripted-effects-multiplayer@0.1.0')
      optional_archives=@('more-infinite-research_5.0.20000.zip','mir-fixture-mir5-scripted-effects-multiplayer_0.1.0.zip')
    }
  )
  Assert-Session ($Selection.Contains('target') -and $Selection['target'] -is [string] -and $Selection.Contains('kind') -and $Selection['kind'] -is [string]) 'requires an admitted multiplayer fixture target'
  $mirRows=@($Selection['mods']|Where-Object { $_ -is [System.Collections.IDictionary] -and $_['name'] -is [string] -and $_['name'] -ceq 'more-infinite-research' -and $_['version'] -is [string] })
  $matches=@($targets|Where-Object {
    $_.fixture_case -ceq $FixtureCase -and $_.target -ceq [string]$Selection['target'] -and $_.kind -ceq [string]$Selection['kind'] -and
    $mirRows.Count -eq 1 -and $mirRows[0]['version'] -ceq $_.mir -and
    $(if($StandaloneIdentityDiscovery){$_.Contains('standalone_identity_discovery') -and $_.standalone_identity_discovery -eq $true}else{-not $_.Contains('standalone_identity_discovery')})
  })
  Assert-Session ($matches.Count -eq 1) 'requires an admitted multiplayer fixture target'
  $target=$matches[0]
  Assert-Session (($Selection['schema'] -is [int] -or $Selection['schema'] -is [long]) -and [int64]$Selection['schema'] -eq 1 -and $Selection['kind'] -ceq $target.kind -and $Selection['factorio_line'] -ceq $target.factorio_line -and $Selection['settings_mode'] -ceq 'Defaults') 'multiplayer fixture profile identity differs'
  Assert-Session ($Selection.Contains('engine') -and $Selection['engine'] -is [System.Collections.IDictionary]) 'multiplayer fixture profile engine is absent'
  $engine=$Selection['engine']
  Assert-Session ($engine.Count -eq 2 -and $engine['version'] -ceq $target.base -and $engine['sha256'] -ceq $target.engine_sha256 -and $EngineSha256 -ceq $target.engine_sha256) 'multiplayer fixture engine differs'
  $expectedMods=@(('base@'+$target.base),'mir-fixture-mir5-active-mods-observer@0.1.0',('more-infinite-research@'+$target.mir))+@($target.fixture_mods)
  Assert-Session ($Selection.Contains('mods') -and @($Selection['mods']).Count -eq $expectedMods.Count) 'multiplayer fixture mod closure count differs'
  $mods=[Collections.Generic.List[string]]::new()
  foreach($mod in @($Selection['mods'])){
    Assert-Session ($mod -is [System.Collections.IDictionary] -and $mod.Count -eq 3 -and $mod['name'] -is [string] -and $mod['version'] -is [string] -and $mod['enabled'] -is [bool] -and $mod['enabled'] -eq $true) 'multiplayer fixture mod row differs'
    [void]$mods.Add(([string]$mod['name'])+'@'+([string]$mod['version']))
  }
  Assert-Session ((@($mods|Sort-Object)-join '|') -ceq (@($expectedMods|Sort-Object)-join '|')) 'multiplayer fixture mod closure differs'
  Assert-Session ($Selection.Contains('archive_sha256') -and $Selection['archive_sha256'] -is [System.Collections.IDictionary]) 'multiplayer fixture archive binding is absent'
  $archives=$Selection['archive_sha256'];$observer='mir-fixture-mir5-active-mods-observer_0.1.0.zip'
  $allowedArchives=@($observer)+@($target.optional_archives)
  Assert-Session ($archives.Contains($observer) -and $archives[$observer] -ceq $target.observer_sha256) 'multiplayer fixture observer archive differs'
  if($target.Contains('mir_archive_sha256')){
    $mirArchive='more-infinite-research_'+$target.mir+'.zip'
    Assert-Session ($target.mir_archive_sha256 -is [string] -and $target.mir_archive_sha256 -cmatch '^[A-F0-9]{64}$' -and $archives.Contains($mirArchive) -and $archives[$mirArchive] -ceq $target.mir_archive_sha256) 'multiplayer fixture MIR archive differs'
  }
  if($target.Contains('fixture_archive_required')){
    $fixtureArchive='mir-fixture-mir5-library-multiplayer_0.1.1.zip'
    Assert-Session ($target.fixture_archive_required -is [bool] -and $target.fixture_archive_required -and $archives.Contains($fixtureArchive) -and $archives[$fixtureArchive] -is [string] -and $archives[$fixtureArchive] -cmatch '^[A-F0-9]{64}$') 'standalone identity discovery fixture archive differs'
  }
  foreach($entry in $archives.GetEnumerator()){
    Assert-Session ($allowedArchives -ccontains [string]$entry.Key -and $entry.Value -is [string] -and $entry.Value -cmatch '^[A-F0-9]{64}$') 'multiplayer fixture archive binding differs'
  }
  Assert-Session ($FixtureCase -ceq 'library-multiplayer' -or $target.target -ceq 'f200') 'only F200 admits non-functional fixture cases'
  return [pscustomobject]$target
}
function Assert-StandaloneIdentityFixtureSource {
  param([Parameter(Mandatory)][string[]]$Sources)
  $matches=@(foreach($candidate in $Sources){
    $source=(Resolve-Path -LiteralPath $candidate).Path
    $infoPath=Join-Path $source 'info.json'
    Assert-Session (Test-Path -LiteralPath $infoPath -PathType Leaf) 'standalone identity discovery fixture info is absent'
    $info=Get-Content -LiteralPath $infoPath -Raw|ConvertFrom-Json -AsHashtable
    if([string]$info.name -ceq 'mir-fixture-mir5-library-multiplayer'){[pscustomobject]@{source=$source;info=$info}}
  })
  Assert-Session ($matches.Count-eq1) 'standalone identity discovery requires one staged Library fixture source'
  $fixture=$matches[0]
  Assert-Session ([string]$fixture.info.version -ceq '0.1.1' -and [string]$fixture.info.factorio_version -ceq '2.1') 'standalone identity discovery fixture identity differs'
  $settingsPath=Join-Path $fixture.source 'settings-updates.lua'
  Assert-Session (Test-Path -LiteralPath $settingsPath -PathType Leaf) 'standalone identity discovery fixture setting definition is absent'
  $settings=Get-Content -LiteralPath $settingsPath -Raw
  $setting=[regex]::Match($settings,'(?s)name\s*=\s*"mir5-library-standalone-identity-discovery".*?default_value\s*=\s*true')
  Assert-Session $setting.Success 'standalone identity discovery fixture setting is not enabled'
  return $fixture
}
function New-StandaloneIdentityFixtureStage {
  param([Parameter(Mandatory)][string[]]$Sources,[Parameter(Mandatory)][string]$OutputRoot)
  $templates=@(foreach($candidate in $Sources){
    $source=(Resolve-Path -LiteralPath $candidate).Path
    $infoPath=Join-Path $source 'info.json'
    if(Test-Path -LiteralPath $infoPath -PathType Leaf){
      $info=Get-Content -LiteralPath $infoPath -Raw|ConvertFrom-Json -AsHashtable
      if([string]$info.name-ceq'mir-fixture-mir5-library-multiplayer'){[pscustomobject]@{source=$source;info=$info}}
    }
  })
  Assert-Session ($templates.Count-eq1) 'standalone identity discovery requires one canonical Library fixture template'
  $template=$templates[0]
  $f210Info=Join-Path $template.source 'info-f210.json'
  Assert-Session (Test-Path -LiteralPath $f210Info -PathType Leaf) 'standalone identity discovery requires the canonical F210 fixture metadata'
  $stage=Join-Path $OutputRoot 'standalone-identity-fixture-source'
  Assert-Session (-not(Test-Path -LiteralPath $stage)) 'standalone identity discovery fixture stage already exists'
  $null=New-Item -ItemType Directory -Path $stage
  $info=Get-Content -LiteralPath $f210Info -Raw|ConvertFrom-Json -AsHashtable
  Assert-Session ([string]$info.name-ceq'mir-fixture-mir5-library-multiplayer' -and [string]$info.version-ceq'0.1.0' -and [string]$info.factorio_version-ceq'2.1') 'standalone identity discovery F210 fixture template differs'
  $info.version='0.1.1'
  [IO.File]::WriteAllText((Join-Path $stage 'info.json'),($info|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
  foreach($name in @('control.lua','README.md')){
    $source=Join-Path $template.source $name
    Assert-Session (Test-Path -LiteralPath $source -PathType Leaf) "standalone identity discovery fixture template lacks $name"
    [IO.File]::Copy($source,(Join-Path $stage $name),$false)
  }
  $settingsSource=Join-Path $template.source 'settings-updates.lua'
  $settings=[IO.File]::ReadAllText($settingsSource)
  $matches=[regex]::Matches($settings,'default_value\s*=\s*false')
  Assert-Session ($matches.Count-eq1) 'standalone identity discovery setting template differs'
  $settings=[regex]::Replace($settings,'default_value\s*=\s*false','default_value = true',1)
  [IO.File]::WriteAllText((Join-Path $stage 'settings-updates.lua'),$settings,[Text.UTF8Encoding]::new($false))
  $archiveDirectory=Join-Path $OutputRoot 'standalone-identity-fixture-archive'
  $null=New-Item -ItemType Directory -Path $archiveDirectory
  $archive=Join-Path $archiveDirectory 'mir-fixture-mir5-library-multiplayer_0.1.1.zip'
  $stream=[IO.File]::Open($archive,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{
    $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
    try{
      foreach($file in @(Get-ChildItem -LiteralPath $stage -Recurse -File|Sort-Object FullName)){
        $entry=$zip.CreateEntry('mir-fixture-mir5-library-multiplayer_0.1.1/'+[IO.Path]::GetRelativePath($stage,$file.FullName).Replace('\','/'),[IO.Compression.CompressionLevel]::Optimal)
        $entryStream=$entry.Open();$input=[IO.File]::OpenRead($file.FullName)
        try{$input.CopyTo($entryStream)}finally{$input.Dispose();$entryStream.Dispose()}
      }
    }finally{$zip.Dispose()}
  }finally{$stream.Dispose()}
  $fixture=Assert-StandaloneIdentityFixtureSource -Sources @($stage)
  Assert-MIRLibraryFixtureArchive -Archive $archive -SourceDirectory $fixture.source
  return [pscustomobject]@{source=$fixture.source;archive=$archive;sha256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToUpperInvariant()}
}
function Get-StandaloneIdentityFixtureSources {
  param(
    [Parameter(Mandatory)][string[]]$Sources,
    [Parameter(Mandatory)][string]$LibraryFixtureSource,
    [Parameter(Mandatory)][string]$StagedLibraryFixtureSource,
    [Parameter(Mandatory)][string]$RepoRoot
  )
  $canonicalObserver=(Resolve-Path -LiteralPath (Join-Path $RepoRoot 'tests/fixtures/active-mods-observer')).Path
  $canonicalInfo=Get-Content -LiteralPath (Join-Path $canonicalObserver 'info.json') -Raw|ConvertFrom-Json -AsHashtable
  Assert-Session ([string]$canonicalInfo.name-ceq'mir-fixture-mir5-active-mods-observer' -and [string]$canonicalInfo.version-ceq'0.1.0' -and [string]$canonicalInfo.factorio_version-ceq'2.1') 'standalone identity discovery canonical observer source differs'
  $library=(Resolve-Path -LiteralPath $LibraryFixtureSource).Path
  $staged=(Resolve-Path -LiteralPath $StagedLibraryFixtureSource).Path
  $result=[Collections.Generic.List[string]]::new();$libraryCount=0;$observerCount=0
  foreach($candidate in $Sources){
    $source=(Resolve-Path -LiteralPath $candidate).Path
    $info=Get-Content -LiteralPath (Join-Path $source 'info.json') -Raw|ConvertFrom-Json -AsHashtable
    if([string]$info.name-ceq'mir-fixture-mir5-library-multiplayer'){
      Assert-Session ($source-ieq$library) 'standalone identity discovery Library source differs from its canonical template'
      $libraryCount++;$result.Add($staged)
    }elseif([string]$info.name-ceq'mir-fixture-mir5-active-mods-observer'){
      Assert-Session ($source-ieq$canonicalObserver) 'standalone identity discovery observer source differs from its canonical source'
      $observerCount++;$result.Add($canonicalObserver)
    }else{$result.Add($source)}
  }
  Assert-Session ($libraryCount-eq1) 'standalone identity discovery requires one canonical Library fixture source'
  Assert-Session ($observerCount -le 1) 'standalone identity discovery observer source is duplicated'
  if($observerCount-eq0){$result.Add($canonicalObserver)}
  $actualObserver=@($result|Where-Object {$_-ieq$canonicalObserver})
  Assert-Session ($actualObserver.Count-eq1) 'standalone identity discovery requires one verified canonical observer source'
  return @($result.ToArray())
}
function Install-StandaloneIdentityFixtureArchive {
  param([Parameter(Mandatory)][string]$Library,[Parameter(Mandatory)]$Fixture)
  Assert-MIRLibraryIdle -WaitMilliseconds 3000
  $lockPath=Join-Path $Library '.mir-library-standalone-identity.lock'
  $lock=[IO.File]::Open($lockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try{
    $destination=Join-Path $Library 'mir-fixture-mir5-library-multiplayer_0.1.1.zip'
    Assert-Session (-not(Test-Path -LiteralPath $destination)) 'standalone identity discovery archive already exists in the direct library'
    [IO.File]::Copy([string]$Fixture.archive,$destination,$false)
    Assert-Session ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToUpperInvariant() -ceq [string]$Fixture.sha256) 'standalone identity discovery archive copy differs'
    return [pscustomobject]@{path=$destination;sha256=[string]$Fixture.sha256;lock=$lock;removed=$false}
  }catch{$lock.Dispose();if(Test-Path -LiteralPath $lockPath){[IO.File]::Delete($lockPath)};throw}
}
function Remove-StandaloneIdentityFixtureArchive {
  param([Parameter(Mandatory)]$Install)
  if($Install.removed){return}
  try{
    Assert-MIRLibraryIdle -WaitMilliseconds 3000
    Assert-Session (Test-Path -LiteralPath $Install.path -PathType Leaf) 'standalone identity discovery archive disappeared before restoration'
    Assert-Session ((Get-FileHash -LiteralPath $Install.path -Algorithm SHA256).Hash.ToUpperInvariant() -ceq [string]$Install.sha256) 'standalone identity discovery archive changed before restoration'
    [IO.File]::Delete([string]$Install.path)
    $Install.removed=$true
  }finally{
    $lockPath=Join-Path (Split-Path -Parent $Install.path) '.mir-library-standalone-identity.lock'
    $Install.lock.Dispose()
    if(Test-Path -LiteralPath $lockPath){[IO.File]::Delete($lockPath)}
  }
}
function Invoke-MultiplayerFixturePreparation {
  param(
    [Parameter(Mandatory)][string]$ArchiveLibrary,
    [Parameter(Mandatory)][string]$FactorioBin,
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][string[]]$FixtureSources,
    [Parameter(Mandatory)][string]$ExpectedMIRArchiveSha256,
    [Parameter(Mandatory)][string]$FixtureCase,
    [Parameter(Mandatory)][string]$PreparationRoot,
    [Parameter(Mandatory)][string]$RepoRoot,
    [switch]$StandaloneIdentityDiscovery,
    $DiscoveryFixture,
    [scriptblock]$CreateOnlyInvoker
  )
  # A staged discovery fixture remains installed only after every CreateOnly
  # receipt and byte binding has been accepted.  Any malformed/missing receipt
  # exits through this one cleanup finally before the caller can start a host.
  $install=$null;$completed=$false
  try {
    if($StandaloneIdentityDiscovery){$install=Install-StandaloneIdentityFixtureArchive -Library $ArchiveLibrary -Fixture $DiscoveryFixture}
    $nativeArguments=@{
      ArchiveLibrary=$ArchiveLibrary;FactorioBin=$FactorioBin;ProfilePath=$ProfilePath;FixtureSources=$FixtureSources
      ExpectedMIRArchiveSha256=$ExpectedMIRArchiveSha256;ActiveModsObserver='mir-fixture-mir5-active-mods-observer'
      CaseName=$FixtureCase;OutputRoot=$PreparationRoot;CreateOnly=$true;ExpectedPeakMemoryMiB=4096;TimeoutSeconds=180;RepoRoot=$RepoRoot
    }
    if($null-ne$CreateOnlyInvoker){& $CreateOnlyInvoker $nativeArguments|Out-Null}
    else{& (Join-Path $PSScriptRoot 'Invoke-NativeFixture.ps1') @nativeArguments|Out-Null}
    $prepared=Get-Content -LiteralPath (Join-Path $PreparationRoot 'result.json') -Raw|ConvertFrom-Json
    Assert-Session ($prepared.status -ceq 'passed-private-native-runtime-load-only') 'native world preparation failed'
    if($StandaloneIdentityDiscovery){
      $actualFixture=@($prepared.fixtures|Where-Object {[IO.Path]::GetFileName([string]$_.archive) -ceq 'mir-fixture-mir5-library-multiplayer_0.1.1.zip'})
      Assert-Session ($actualFixture.Count-eq1 -and [string]$actualFixture[0].source -ceq [string]$DiscoveryFixture.source -and [string]$actualFixture[0].sha256 -ceq [string]$DiscoveryFixture.sha256) 'standalone identity discovery fixture bytes differ from its profile binding'
    }
    $seed=Join-Path $PreparationRoot 'write-data/saves/seed.zip'
    Assert-Session ((Get-FileHash -LiteralPath $seed).Hash -ceq $prepared.seed_sha256) 'prepared seed differs'
    $completed=$true
    return [pscustomobject]@{prepared=$prepared;seed=$seed;install=$install}
  } finally {
    if(-not $completed -and $null-ne$install){Remove-StandaloneIdentityFixtureArchive -Install $install}
  }
}
$output=Resolve-MIR441RecoveryScratchPath -Path $OutputRoot
Assert-Session (-not(Test-Path -LiteralPath $output) -or @(Get-ChildItem -LiteralPath $output -Force).Count -eq 0) 'output is not empty'
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
$library=(Resolve-Path -LiteralPath $ArchiveLibrary).Path
$templateProfile=(Resolve-Path -LiteralPath $ProfilePath).Path
$profile=$templateProfile
$selection=Get-Content -LiteralPath $profile -Raw|ConvertFrom-Json -AsHashtable
$discoveryFixture=$null;$discoveryInstall=$null;$fixtureSourcesForRun=@($FixtureSources)
if($StandaloneIdentityDiscovery){
  # The checked-in functional profile is a template only.  The actual
  # environmental packet is assembled below from the standalone engine, C563,
  # A15 and the staged 0.1.1 fixture; it never relabels the FE4/2E profile.
  $null=Assert-MultiplayerFixtureSelection -Selection $selection -EngineSha256 'FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060' -FixtureCase 'library-multiplayer'
  $discoveryFixture=New-StandaloneIdentityFixtureStage -Sources $FixtureSources -OutputRoot $output
  $fixtureSourcesForRun=Get-StandaloneIdentityFixtureSources -Sources $FixtureSources -LibraryFixtureSource (Join-Path $repo 'tests/fixtures/library-multiplayer') -StagedLibraryFixtureSource $discoveryFixture.source -RepoRoot $repo
  $selection=[ordered]@{
    schema=1;kind='mir5-library-standalone-identity-discovery-f210-selection';target='standalone-identity-discovery';factorio_line='2.1';settings_mode='Defaults'
    engine=[ordered]@{version='2.1.23';sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38'}
    mods=@(
      [ordered]@{name='base';version='2.1.23';enabled=$true},
      [ordered]@{name='mir-fixture-mir5-active-mods-observer';version='0.1.0';enabled=$true},
      [ordered]@{name='more-infinite-research';version='5.0.21000';enabled=$true},
      [ordered]@{name='mir-fixture-mir5-library-multiplayer';version='0.1.1';enabled=$true}
    )
    archive_sha256=[ordered]@{
      'mir-fixture-mir5-active-mods-observer_0.1.0.zip'='A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0'
      'more-infinite-research_5.0.21000.zip'='C563CB5B96C9E64CB3373BDB60CF5C8B7D3C97E93EADB8F924443C703CDC024D'
      'mir-fixture-mir5-library-multiplayer_0.1.1.zip'=$discoveryFixture.sha256
    }
  }
  $profile=Join-Path $output 'standalone-identity-selection.json'
  [IO.File]::WriteAllText($profile,($selection|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}
$target=Assert-MultiplayerFixtureSelection -Selection $selection -EngineSha256 (Get-FileHash -LiteralPath $engine).Hash -FixtureCase $FixtureCase -StandaloneIdentityDiscovery:$StandaloneIdentityDiscovery
Assert-Session ($FixtureCase -ceq 'library-multiplayer' -or $SessionExpectedPeakMemoryMiB -eq 8192) 'only the functional Library session may use the calibrated peak override'
Assert-Session (-not $StandaloneIdentityDiscovery -or ($FixtureCase -ceq 'library-multiplayer' -and $SessionExpectedPeakMemoryMiB -eq 7168 -and -not $CollectProcessMemoryObservations)) 'standalone identity discovery differs from its bounded Library-only contract'
Assert-Session (-not $StandaloneIdentityDiscovery -or $ExpectedMIRArchiveSha256.ToUpperInvariant() -ceq [string]$target.mir_archive_sha256) 'standalone identity discovery MIR archive differs'
$engineData=Join-Path (Get-Item -LiteralPath $engine).Directory.Parent.Parent.FullName 'data'
$preparation=Join-Path $output 'preparation'
$preparationResult=Invoke-MultiplayerFixturePreparation -ArchiveLibrary $library -FactorioBin $engine -ProfilePath $profile -FixtureSources $fixtureSourcesForRun -ExpectedMIRArchiveSha256 $ExpectedMIRArchiveSha256 -FixtureCase $FixtureCase -PreparationRoot $preparation -RepoRoot $repo -StandaloneIdentityDiscovery:$StandaloneIdentityDiscovery -DiscoveryFixture $discoveryFixture
$prepared=$preparationResult.prepared;$seed=[string]$preparationResult.seed;$discoveryInstall=$preparationResult.install
$activation=$null;$resources=$null;$failure=$null
$record=[ordered]@{
  kind=$(if($StandaloneIdentityDiscovery){'MIR5StandaloneIdentityDiscoveryNativeResultV1'}else{switch($FixtureCase){'library-multiplayer'{'MIR5LibraryMultiplayerNativeResultV1'};'library-paired-browser'{'MIR5LibraryPairedBrowserNativeResultV1'};default{'MIR5ScriptedEffectsMultiplayerNativeResultV1'}}});case=$FixtureCase;status='started';source_head=$prepared.source_head
  engine=$prepared.engine;profile=$prepared.profile;fixtures=$prepared.fixtures;mir_archive=$prepared.mir_archive
  preparation=$prepared;session_expected_peak_memory_mib=$SessionExpectedPeakMemoryMiB;release_qualification=$false;visual_review=$false
  standalone_identity_discovery=if($StandaloneIdentityDiscovery){[ordered]@{fixture_source=$discoveryFixture.source;fixture_archive_sha256=[string]$selection.archive_sha256['mir-fixture-mir5-library-multiplayer_0.1.1.zip'];environmental_only=$true}}else{$null}
  harness_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
}
try {
  $resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot (Join-Path $output 'session') -ExpectedPeakMemoryMiB $SessionExpectedPeakMemoryMiB -MaxNewOutputMiB 512 -UseExactOutputRoot
  $null=New-Item -ItemType Directory -Path $resources.root
  $serverWrite=Join-Path $resources.root 'server'
  $null=New-Item -ItemType Directory -Path $serverWrite
  $null=New-Item -ItemType Directory -Path (Join-Path $serverWrite 'saves')
  $serverConfig=Join-Path $resources.root 'server.ini'
  New-MIRDirectLibraryStartupConfig -Path $serverConfig -EngineDataDirectory $engineData -WriteDataDirectory $serverWrite
  $settings=Get-Content -LiteralPath (Join-Path $engineData 'server-settings.example.json') -Raw|ConvertFrom-Json -AsHashtable
  $settings.name='MIR5 private loopback clients';$settings.description=''
  $settings.visibility=@{public=$false;lan=$false};$settings.require_user_verification=$false
  foreach($name in @('username','password','token','game_password')){$settings[$name]=''}
  $settings.max_players=2;$settings.auto_pause=$false;$settings.autosave_interval=0
  $serverSettings=Join-Path $resources.root 'server-settings.json'
  [IO.File]::WriteAllText($serverSettings,($settings|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
  # Let Windows allocate available loopback ports. Fixed ports can be in its
  # excluded ranges (the first native run failed with WSAEACCES/10013).
  $udpProbes=@();$tcpProbe=$null
  try {
    foreach($index in 0..2){
      $probe=[Net.Sockets.UdpClient]::new([Net.Sockets.AddressFamily]::InterNetwork)
      $probe.Client.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback,0))
      $udpProbes+=,$probe
    }
    $udpPorts=@($udpProbes|ForEach-Object {[int]$_.Client.LocalEndPoint.Port})
    $tcpProbe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$tcpProbe.Start()
    $rconPort=[int]$tcpProbe.LocalEndpoint.Port
  } finally {
    foreach($probe in $udpProbes){$probe.Dispose()}
    if($null -ne $tcpProbe){$tcpProbe.Stop()}
  }
  $serverPort=$udpPorts[0];$clientIndex=1
  $record.loopback_ports=[ordered]@{udp=$udpPorts;rcon_tcp=$rconPort;selection='OS-assigned temporary loopback bindings, released before native start'}
  $clients=@()
  $rconPassword=[guid]::NewGuid().ToString('D')
  foreach($locale in @('en','de')){
    $write=Join-Path $resources.root ('client-'+$locale)
    $null=New-Item -ItemType Directory -Path $write
    $config=Join-Path $resources.root ('client-'+$locale+'.ini')
    New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $engineData -WriteDataDirectory $write -Graphics
    $text=[IO.File]::ReadAllText($config).Replace('locale=en',('locale='+$locale))
    [IO.File]::WriteAllText($config,$text,[Text.UTF8Encoding]::new($false))
    $name=if($StandaloneIdentityDiscovery){'standalone-'+$locale}elseif($locale -ceq 'en'){'MIR5English'}else{'MIR5Deutsch'}
    # Isolated disposable identities contain no online token or personal data.
    $player=@{'service-token'='';'last-played-version'=@{game_version=$target.base;build_version=$target.build_version;build_mode='full';platform='win64'}}
    if(-not $StandaloneIdentityDiscovery){$player['service-username']=$name}
    [IO.File]::WriteAllText((Join-Path $write 'player-data.json'),($player|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    $clients+=@{name=$name;locale=$locale;config=$config;write_data=$write;port=$udpPorts[$clientIndex]};$clientIndex++
  }
  $pairedArm=$null
  if($FixtureCase -ceq 'library-paired-browser'){
    Assert-Session ($selection.kind -ceq 'mir5-library-paired-browser-f200-native-selection') 'paired browser profile kind differs'
    $mirRows=@($selection.mods | Where-Object {[string]$_.name -ceq 'more-infinite-research'})
    $armRows=@($selection.mods | Where-Object {[string]$_.name -cmatch '^mir-fixture-mir5-library-paired-browser-arm-(published|mir5)$'})
    Assert-Session ($mirRows.Count -eq 1 -and $armRows.Count -eq 1) 'paired browser profile arm selection differs'
    $armName=[string]$armRows[0].name
    if($armName -ceq 'mir-fixture-mir5-library-paired-browser-arm-published' -and [string]$mirRows[0].version -ceq '4.7.20002'){$pairedArm='published'}
    elseif($armName -ceq 'mir-fixture-mir5-library-paired-browser-arm-mir5' -and [string]$mirRows[0].version -ceq '5.0.20000'){$pairedArm='mir5'}
    else{throw '[mir5-multiplayer-fixture] paired browser profile MIR arm/version differs'}
  }
  $hashes=@{};foreach($entry in $selection.archive_sha256.GetEnumerator()){$hashes[$entry.Key]=$entry.Value}
  $hashes[[IO.Path]::GetFileName([string]$prepared.mir_archive.path)]=$ExpectedMIRArchiveSha256.ToUpperInvariant()
  foreach($fixture in $prepared.fixtures){$hashes[[IO.Path]::GetFileName([string]$fixture.archive)]=$fixture.sha256}
  $activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $engineData -ProfilePath $profile -ArchiveHashes $hashes -SettingsMode Defaults
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $activation
  # Validate the entire fixed launch set before starting the governed tree.
  Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments @('--config',$serverConfig,'--mod-directory',$library,'--disable-audio','--no-log-rotation','--start-server',$seed,'--server-settings',$serverSettings,'--bind','127.0.0.1','--port',[string]$serverPort,'--rcon-bind',('127.0.0.1:'+ $rconPort),'--rcon-password',$rconPassword)
  $clientGraphics=@(if($FixtureCase-ceq'scripted-effects-multiplayer'){'--force-graphics-preset';'low';'--video-memory-usage';'low'})
  foreach($client in $clients){Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments (@('--config',$client.config,'--mod-directory',$library,'--disable-audio','--no-log-rotation','--window-size','1280x720','--mp-connect',('127.0.0.1:'+ $serverPort),'--port',[string]$client.port)+$clientGraphics)}
  $screenshots=@(
    if($FixtureCase-ceq'library-multiplayer' -and -not $StandaloneIdentityDiscovery){
      foreach($client in $clients){foreach($stage in @('availability','initial','settled','rejoin','restart')){Join-Path $client.write_data ('script-output/mir5-library-multiplayer/'+$stage+'-*.png')}}
    }elseif($FixtureCase-ceq'library-paired-browser'){
      foreach($client in $clients){foreach($stage in @('first-open','search','refresh','reopen')){Join-Path $client.write_data ('script-output/mir5-library-paired-browser/'+$stage+'-*.png')}}
    }
  )
  $spec=[ordered]@{case=$FixtureCase;engine=$engine;engine_sha256=$selection.engine.sha256;archive_library=$library;workroot=$resources.root;seed_save=$seed;seed_sha256=$prepared.seed_sha256;server_config=$serverConfig;server_settings=$serverSettings;server_write_data=$serverWrite;port=$serverPort;clients=$clients;expected_screenshots=$screenshots;rcon_port=$rconPort;rcon_password=$rconPassword}
  if($StandaloneIdentityDiscovery){
    $spec.standalone_identity_discovery=$true
    $spec.identity_discovery=[ordered]@{engine_sha256=[string]$target.engine_sha256;mir_archive_sha256=[string]$target.mir_archive_sha256;observer_archive_sha256=[string]$target.observer_sha256;fixture_version='0.1.1';join_budget_seconds=180;environmental_only=$true}
  }
  if($FixtureCase -ceq 'library-multiplayer'){
    $spec.library_witness_target=[ordered]@{engine_sha256=[string]$target.engine_sha256;base=[string]$target.base;mir=[string]$target.mir}
    if($target.PSObject.Properties['api_client_consumers']){
      Assert-Session ($target.api_client_consumers -is [bool] -and $target.api_client_consumers) 'API client consumer target differs'
      $spec.api_client_consumers=$true
    }
  }
  if($null -ne $pairedArm){$spec.paired_arm=$pairedArm}
  if($CollectProcessMemoryObservations){
    Assert-Session ($FixtureCase -cin @('library-multiplayer','library-paired-browser')) 'process memory observations require a named Library fixture'
    $spec.process_memory_observations=$true
  }
  $specPath=Join-Path $resources.root 'session-spec.json'
  [IO.File]::WriteAllText($specPath,($spec|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $record.session_spec_sha256=(Get-FileHash -LiteralPath $specPath).Hash
  $pwsh=(Get-Command pwsh -ErrorAction Stop).Source
  $sessionArguments=@('-NoLogo','-NoProfile','-File',(Join-Path $PSScriptRoot 'Invoke-MultiplayerSession.ps1'),'-SpecPath',$specPath)
  $processArguments=@{Context=$resources;FilePath=$pwsh;Arguments=$sessionArguments;TimeoutSeconds=$(if($StandaloneIdentityDiscovery){220}else{1000})}
  if(-not $StandaloneIdentityDiscovery){$processArguments.FactorioSteamIdentity=$true}
  $record.process=Invoke-MIRNativeProbeProcess @processArguments
  $session=Get-Content -LiteralPath (Join-Path $resources.root 'session.json') -Raw|ConvertFrom-Json
  Assert-Session ($session.status -ceq $(if($StandaloneIdentityDiscovery){'passed-private-standalone-identity-discovery'}else{'passed-private-two-client-session'})) 'native client session did not pass'
  $record.session=$session
  $record.status=$(if($StandaloneIdentityDiscovery){'passed-private-standalone-identity-discovery-fixture'}else{'passed-private-two-client-fixture'})
} catch {
  $failure=$_;$record.status='failed';$record.failure=$_.Exception.Message
  $record.resource_admission=$_.Exception.Data['mir441_resource_admission']
} finally {
  try {
    if($null -ne $activation -and -not $activation.closed){$record.library_control_restoration=Complete-MIRLibraryActivation -Activation $activation}
    if($null-ne$discoveryInstall){Remove-StandaloneIdentityFixtureArchive -Install $discoveryInstall}
    $record.input_save_byte_identical=(Get-FileHash -LiteralPath $seed).Hash -ceq $prepared.seed_sha256
    Assert-Session $record.input_save_byte_identical 'original disposable seed changed'
  } catch {if($null -eq $failure){$failure=$_;$record.status='failed';$record.failure=$_.Exception.Message}}
  if($null -ne $resources){$record.process_runs=@($resources.runs.ToArray());Write-MIRNativeProbeResult -Context $resources -Record $record}
  elseif($null -ne $record.resource_admission){
    # Admission precedes context allocation. Preserve only bounded refusal
    # facts here; the full preparation/session record can contain secrets.
    try{
      $refusal=[ordered]@{
        kind='MIR5MultiplayerAdmissionRefusalV1';status='refused-before-session';case=$record.case
        source_head=$record.source_head;harness_sha256=$record.harness_sha256;engine=$record.engine
        profile_sha256=$record.profile.sha256;mir_archive_sha256=$record.mir_archive.sha256
        failure=$record.failure;resource_admission=$record.resource_admission
        native_session_started=$false;release_qualification=$false
      }
      $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($refusal|ConvertTo-Json -Depth 12 -Compress)+"`n")
      Assert-Session ($bytes.Length -le 64KB) 'admission receipt exceeds diagnostic reserve'
      $path=Join-Path $output 'session-admission-refusal.json'
      $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
      try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    }catch{
      # A diagnostic failure must not overwrite the original admission error.
      if($null -ne $failure){$failure.Exception.Data['admission_receipt_failure']=$_.Exception.Message}
    }
  }
}
if($null -ne $failure){throw $failure}
[pscustomobject]$record
