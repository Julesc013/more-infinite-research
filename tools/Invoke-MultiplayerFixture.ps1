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
    [string]$ExpectedMIRArchiveSha256,
    [int]$SessionExpectedPeakMemoryMiB=0,
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
      fixture_case='library-multiplayer';target='f210-standalone'
      kind='mir5-library-multiplayer-standalone-f210-native-selection';factorio_line='2.1';base='2.1.23'
      engine_sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38';mir='5.0.21000';build_version=87750
      observer_sha256='A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0'
      fixture_mods=@('mir-fixture-mir5-library-multiplayer@0.1.0')
      optional_archives=@('more-infinite-research_5.0.21000.zip','mir-fixture-mir5-library-multiplayer_0.1.0.zip')
      standalone_f210=$true
    }
    [ordered]@{
      fixture_case='library-multiplayer';target='f210-standalone'
      kind='mir5-library-api-consumers-standalone-f210-native-selection';factorio_line='2.1';base='2.1.23'
      engine_sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38';mir='5.0.21000';build_version=87750
      observer_sha256='A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0'
      mir_archive_sha256='2ABAF369E020D8AD18A0C04940A8811BECFA5E63E5B479C668E2D3A3123D032B'
      fixture_mods=@('mir-fixture-mir5-library-multiplayer@0.1.0','mir-fixture-mir5-api-alpha@0.1.0','mir-fixture-mir5-api-beta@0.1.0')
      optional_archives=@('more-infinite-research_5.0.21000.zip','mir-fixture-mir5-library-multiplayer_0.1.0.zip','mir-fixture-mir5-api-alpha_0.1.0.zip','mir-fixture-mir5-api-beta_0.1.0.zip')
      api_consumer_archive_sha256=[ordered]@{
        'mir-fixture-mir5-api-alpha_0.1.0.zip'='DB5ED843FA9D85A1ABDC22595E62D315CA1A2191C846208079F85D4D016CE904'
        'mir-fixture-mir5-api-beta_0.1.0.zip'='690004F145E8B0DD52B4030BD8B27F7B581495EEFAAC5CB3A2F30A23FCA08951'
      }
      standalone_f210=$true;api_client_consumers=$true
    }
    [ordered]@{
      fixture_case='library-multiplayer';target='f210-standalone'
      kind='mir5-library-api-consumers-current-standalone-f210-native-selection';factorio_line='2.1';base='2.1.23'
      engine_sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38';mir='5.0.21000';build_version=87750
      observer_sha256='A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0'
      mir_archive_sha256='A8D0A4590154F3106E59BDB269F1AEB3ED8CC523F18F00ED7D76DC89059F5B8D'
      fixture_mods=@('mir-fixture-mir5-library-multiplayer@0.1.0','mir-fixture-mir5-api-alpha@0.1.0','mir-fixture-mir5-api-beta@0.1.0')
      optional_archives=@('more-infinite-research_5.0.21000.zip','mir-fixture-mir5-library-multiplayer_0.1.0.zip','mir-fixture-mir5-api-alpha_0.1.0.zip','mir-fixture-mir5-api-beta_0.1.0.zip')
      api_consumer_archive_sha256=[ordered]@{
        'mir-fixture-mir5-api-alpha_0.1.0.zip'='DB5ED843FA9D85A1ABDC22595E62D315CA1A2191C846208079F85D4D016CE904'
        'mir-fixture-mir5-api-beta_0.1.0.zip'='690004F145E8B0DD52B4030BD8B27F7B581495EEFAAC5CB3A2F30A23FCA08951'
      }
      session_expected_peak_memory_mib=7168;standalone_f210=$true;api_client_consumers=$true
    }
    [ordered]@{
      fixture_case='library-multiplayer';target='f210-standalone'
      kind='mir5-library-api-consumers-current-space-age-standalone-f210-native-selection';factorio_line='2.1';base='2.1.23'
      engine_sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38';mir='5.0.21000';build_version=87750
      observer_sha256='A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0'
      mir_archive_sha256='A8D0A4590154F3106E59BDB269F1AEB3ED8CC523F18F00ED7D76DC89059F5B8D'
      fixture_mods=@('elevated-rails@2.1.23','quality@2.1.23','recycler@2.1.23','space-age@2.1.23','mir-fixture-mir5-library-multiplayer@0.2.0','mir-fixture-mir5-api-alpha@0.1.0','mir-fixture-mir5-api-beta@0.1.0')
      optional_archives=@('more-infinite-research_5.0.21000.zip','mir-fixture-mir5-library-multiplayer_0.2.0.zip','mir-fixture-mir5-api-alpha_0.1.0.zip','mir-fixture-mir5-api-beta_0.1.0.zip')
      api_consumer_archive_sha256=[ordered]@{
        'mir-fixture-mir5-api-alpha_0.1.0.zip'='DB5ED843FA9D85A1ABDC22595E62D315CA1A2191C846208079F85D4D016CE904'
        'mir-fixture-mir5-api-beta_0.1.0.zip'='690004F145E8B0DD52B4030BD8B27F7B581495EEFAAC5CB3A2F30A23FCA08951'
      }
      session_expected_peak_memory_mib=8192;standalone_f210=$true;api_client_consumers=$true;space_age_library=$true
    }
    [ordered]@{
      fixture_case='library-multiplayer';target='f210-standalone'
      kind='mir5-library-api-consumers-private-credits-standalone-f210-native-selection';factorio_line='2.1';base='2.1.23'
      engine_sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38';mir='5.0.21000';build_version=87750
      observer_sha256='A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0'
      mir_archive_sha256='005D420671270306155CB4AC25E9CF77541202DFA16B206DCC016237619C9AA2'
      fixture_mods=@('mir-fixture-mir5-library-multiplayer@0.3.0','mir-fixture-mir5-api-alpha@0.1.0','mir-fixture-mir5-api-beta@0.1.0')
      optional_archives=@('more-infinite-research_5.0.21000.zip','mir-fixture-mir5-library-multiplayer_0.3.0.zip','mir-fixture-mir5-api-alpha_0.1.0.zip','mir-fixture-mir5-api-beta_0.1.0.zip')
      api_consumer_archive_sha256=[ordered]@{
        'mir-fixture-mir5-api-alpha_0.1.0.zip'='DB5ED843FA9D85A1ABDC22595E62D315CA1A2191C846208079F85D4D016CE904'
        'mir-fixture-mir5-api-beta_0.1.0.zip'='690004F145E8B0DD52B4030BD8B27F7B581495EEFAAC5CB3A2F30A23FCA08951'
      }
      session_expected_peak_memory_mib=7168;standalone_f210=$true;api_client_consumers=$true;private_credit_checks=$true
    }
    [ordered]@{
      fixture_case='library-multiplayer';target='f210-standalone'
      kind='mir5-library-api-consumers-private-credits-space-age-standalone-f210-native-selection';factorio_line='2.1';base='2.1.23'
      engine_sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38';mir='5.0.21000';build_version=87750
      observer_sha256='A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0'
      mir_archive_sha256='005D420671270306155CB4AC25E9CF77541202DFA16B206DCC016237619C9AA2'
      fixture_mods=@('elevated-rails@2.1.23','quality@2.1.23','recycler@2.1.23','space-age@2.1.23','mir-fixture-mir5-library-multiplayer@0.3.0','mir-fixture-mir5-api-alpha@0.1.0','mir-fixture-mir5-api-beta@0.1.0')
      optional_archives=@('more-infinite-research_5.0.21000.zip','mir-fixture-mir5-library-multiplayer_0.3.0.zip','mir-fixture-mir5-api-alpha_0.1.0.zip','mir-fixture-mir5-api-beta_0.1.0.zip')
      api_consumer_archive_sha256=[ordered]@{
        'mir-fixture-mir5-api-alpha_0.1.0.zip'='DB5ED843FA9D85A1ABDC22595E62D315CA1A2191C846208079F85D4D016CE904'
        'mir-fixture-mir5-api-beta_0.1.0.zip'='690004F145E8B0DD52B4030BD8B27F7B581495EEFAAC5CB3A2F30A23FCA08951'
      }
      session_expected_peak_memory_mib=8192;standalone_f210=$true;api_client_consumers=$true;space_age_library=$true;private_credit_checks=$true
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
    if($PSBoundParameters.ContainsKey('ExpectedMIRArchiveSha256')){
      Assert-Session ($ExpectedMIRArchiveSha256 -cmatch '^[A-Fa-f0-9]{64}$' -and $ExpectedMIRArchiveSha256.ToUpperInvariant() -ceq [string]$target.mir_archive_sha256) 'multiplayer fixture expected MIR archive differs'
    }
  }
  if($target.Contains('session_expected_peak_memory_mib')){
    Assert-Session ($Selection.Contains('session_expected_peak_memory_mib') -and ($Selection['session_expected_peak_memory_mib'] -is [int] -or $Selection['session_expected_peak_memory_mib'] -is [long]) -and [int64]$Selection['session_expected_peak_memory_mib'] -eq [int64]$target.session_expected_peak_memory_mib) 'multiplayer fixture session admission differs'
    Assert-Session ($SessionExpectedPeakMemoryMiB -eq [int]$target.session_expected_peak_memory_mib) 'multiplayer fixture expected session admission differs'
  }
  if($target.Contains('space_age_library')){
    Assert-Session ($target.space_age_library -is [bool] -and $target.space_age_library -and $Selection.Contains('space_age_library') -and $Selection['space_age_library'] -is [bool] -and $Selection['space_age_library'] -eq $true) 'multiplayer fixture Space Age Library selection differs'
  }
  if($target.Contains('private_credit_checks')){
    Assert-Session ($target.private_credit_checks -is [bool] -and $target.private_credit_checks -and $Selection.Contains('private_credit_checks') -and $Selection['private_credit_checks'] -is [bool] -and $Selection['private_credit_checks'] -eq $true) 'multiplayer fixture private-credit selection differs'
  }else{
    Assert-Session (-not $Selection.Contains('private_credit_checks')) 'multiplayer fixture unexpected private-credit selection differs'
  }
  if($target.Contains('fixture_archive_required')){
    $fixtureArchive='mir-fixture-mir5-library-multiplayer_0.1.1.zip'
    Assert-Session ($target.fixture_archive_required -is [bool] -and $target.fixture_archive_required -and $archives.Contains($fixtureArchive) -and $archives[$fixtureArchive] -is [string] -and $archives[$fixtureArchive] -cmatch '^[A-F0-9]{64}$') 'standalone identity discovery fixture archive differs'
  }
  if($target.Contains('api_consumer_archive_sha256')){
    $apiArchives=$target.api_consumer_archive_sha256
    Assert-Session ($apiArchives -is [System.Collections.IDictionary] -and $apiArchives.Count-eq2) 'standalone API consumer archive binding differs'
    foreach($entry in $apiArchives.GetEnumerator()){
      Assert-Session ($entry.Key -is [string] -and $entry.Value -is [string] -and $entry.Value -cmatch '^[A-F0-9]{64}$' -and $archives.Contains([string]$entry.Key) -and $archives[[string]$entry.Key] -ceq [string]$entry.Value) "standalone API consumer archive differs: $($entry.Key)"
    }
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
function New-StandaloneF210LibraryFixtureSourceProjection {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [switch]$SpaceAgeLibrary,
    [switch]$PrivateCreditChecks
  )
  # The checked-in fixture retains F200 metadata and its developer README.
  # Every F210 route stages precisely three runtime members. The selected
  # metadata is the only Base/Space Age distinction; it is copied unchanged.
  $canonical=(Resolve-Path -LiteralPath (Join-Path $RepoRoot 'tests/fixtures/library-multiplayer')).Path
  $canonicalFiles=@(Get-ChildItem -LiteralPath $canonical -Recurse -File|Sort-Object FullName)
  $canonicalNames=@($canonicalFiles|ForEach-Object {[IO.Path]::GetRelativePath($canonical,$_.FullName).Replace('\','/')})
  $baseCanonical=@('README.md','control.lua','info-f210.json','info.json','settings-updates.lua')
  $spaceAgeMetadata='info-f210-space-age.json'
  $privateCreditMetadata='info-f210-private-credits.json'
  $knownOptionalMetadata=@($spaceAgeMetadata,$privateCreditMetadata)
  $expectedCanonical=$baseCanonical+@($canonicalNames|Where-Object {$knownOptionalMetadata-ccontains$_})
  Assert-Session ($canonicalNames.Count-eq$expectedCanonical.Count-and ((@($canonicalNames|Sort-Object)-join '|')-ceq(@($expectedCanonical|Sort-Object)-join '|'))) 'standalone F210 canonical Library fixture members differ'
  $f200Info=Get-Content -LiteralPath (Join-Path $canonical 'info.json') -Raw|ConvertFrom-Json -AsHashtable
  $f210BaseInfo=Get-Content -LiteralPath (Join-Path $canonical 'info-f210.json') -Raw|ConvertFrom-Json -AsHashtable
  Assert-Session ([string]$f200Info.name-ceq'mir-fixture-mir5-library-multiplayer' -and [string]$f200Info.version-ceq'0.1.0' -and [string]$f200Info.factorio_version-ceq'2.0') 'standalone F210 canonical F200 fixture metadata differs'
  Assert-Session ([string]$f210BaseInfo.name-ceq[string]$f200Info.name -and [string]$f210BaseInfo.version-ceq[string]$f200Info.version -and [string]$f210BaseInfo.factorio_version-ceq'2.1' -and ((@($f210BaseInfo.dependencies)-join '|')-ceq'base >= 2.1.23|more-infinite-research = 5.0.21000')) 'standalone F210 canonical Base fixture metadata differs'
  $metadata=if($PrivateCreditChecks){$privateCreditMetadata}elseif($SpaceAgeLibrary){$spaceAgeMetadata}else{'info-f210.json'}
  if($SpaceAgeLibrary){
    Assert-Session ($canonicalNames-ccontains$spaceAgeMetadata) 'standalone F210 Space Age fixture metadata is absent'
    $f210SpaceAgeInfo=Get-Content -LiteralPath (Join-Path $canonical $spaceAgeMetadata) -Raw|ConvertFrom-Json -AsHashtable
    Assert-Session ([string]$f210SpaceAgeInfo.name-ceq[string]$f200Info.name -and [string]$f210SpaceAgeInfo.version-ceq'0.2.0' -and [string]$f210SpaceAgeInfo.factorio_version-ceq'2.1' -and ((@($f210SpaceAgeInfo.dependencies)-join '|')-ceq'base >= 2.1.23|space-age >= 2.1.23|more-infinite-research = 5.0.21000')) 'standalone F210 Space Age fixture metadata differs'
  }
  if($PrivateCreditChecks){
    Assert-Session ($canonicalNames-ccontains$privateCreditMetadata) 'standalone F210 private-credit fixture metadata is absent'
    $f210PrivateCreditInfo=Get-Content -LiteralPath (Join-Path $canonical $privateCreditMetadata) -Raw|ConvertFrom-Json -AsHashtable
    Assert-Session ([string]$f210PrivateCreditInfo.name-ceq[string]$f200Info.name -and [string]$f210PrivateCreditInfo.version-ceq'0.3.0' -and [string]$f210PrivateCreditInfo.factorio_version-ceq'2.1' -and ((@($f210PrivateCreditInfo.dependencies)-join '|')-ceq'base >= 2.1.23|? space-age >= 2.1.23|more-infinite-research = 5.0.21000')) 'standalone F210 private-credit fixture metadata differs'
  }
  $stage=Join-Path $OutputRoot 'standalone-f210-library-fixture-source'
  Assert-Session (-not(Test-Path -LiteralPath $stage)) 'standalone F210 fixture source stage already exists'
  $null=New-Item -ItemType Directory -Path $stage
  $bindings=[ordered]@{
    'control.lua'='control.lua'
    'settings-updates.lua'='settings-updates.lua'
    'info.json'=$metadata
  }
  foreach($entry in $bindings.GetEnumerator()){[IO.File]::Copy((Join-Path $canonical $entry.Value),(Join-Path $stage $entry.Key),$false)}
  $stageNames=@(Get-ChildItem -LiteralPath $stage -Recurse -File|ForEach-Object {[IO.Path]::GetRelativePath($stage,$_.FullName).Replace('\','/')})
  $runtimeNames=@($bindings.Keys|Sort-Object)
  Assert-Session ($stageNames.Count-eq$runtimeNames.Count-and ((@($stageNames|Sort-Object)-join '|')-ceq($runtimeNames-join '|'))) 'standalone F210 fixture projection members differ'
  foreach($entry in $bindings.GetEnumerator()){
    Assert-Session ((Get-FileHash -LiteralPath (Join-Path $stage $entry.Key) -Algorithm SHA256).Hash.ToUpperInvariant()-ceq(Get-FileHash -LiteralPath (Join-Path $canonical $entry.Value) -Algorithm SHA256).Hash.ToUpperInvariant()) "standalone F210 fixture projection bytes differ: $($entry.Key)"
  }
  $selectedCanonicalMembers=@($bindings.Values|Sort-Object -Unique)
  $excluded=@($canonicalNames|Where-Object {$selectedCanonicalMembers-cnotcontains$_}|Sort-Object)
  return [pscustomobject]@{source=$stage;canonical_source=$canonical;members=@($bindings.Keys|Sort-Object|ForEach-Object {$sourceName=if($_-ceq'info.json'){$metadata}else{$_};[ordered]@{path=$_;source=$sourceName;sha256=(Get-FileHash -LiteralPath (Join-Path $stage $_) -Algorithm SHA256).Hash.ToUpperInvariant()}});source_metadata=$metadata;excluded_canonical_members=$excluded}
}
function New-StandaloneIdentityObserverSourceProjection {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$ArchiveLibrary,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedArchiveSha256
  )
  # info-f200.json is alternate-engine packaging metadata.  The immutable F210
  # A15 container intentionally consists only of its two 2.1 runtime members.
  $canonical=(Resolve-Path -LiteralPath (Join-Path $RepoRoot 'tests/fixtures/active-mods-observer')).Path
  $canonicalFiles=@(Get-ChildItem -LiteralPath $canonical -Recurse -File|Sort-Object FullName)
  $canonicalNames=@($canonicalFiles|ForEach-Object {[IO.Path]::GetRelativePath($canonical,$_.FullName).Replace('\','/')})
  $expectedCanonical=@('data-final-fixes.lua','info-f200.json','info.json')
  Assert-Session ($canonicalNames.Count-eq$expectedCanonical.Count-and ((@($canonicalNames|Sort-Object)-join '|')-ceq(@($expectedCanonical|Sort-Object)-join '|'))) 'standalone identity discovery canonical observer source members differ'
  $info=Get-Content -LiteralPath (Join-Path $canonical 'info.json') -Raw|ConvertFrom-Json -AsHashtable
  $f200Info=Get-Content -LiteralPath (Join-Path $canonical 'info-f200.json') -Raw|ConvertFrom-Json -AsHashtable
  Assert-Session ([string]$info.name-ceq'mir-fixture-mir5-active-mods-observer' -and [string]$info.version-ceq'0.1.0' -and [string]$info.factorio_version-ceq'2.1') 'standalone identity discovery canonical F210 observer metadata differs'
  Assert-Session ([string]$f200Info.name-ceq[string]$info.name -and [string]$f200Info.version-ceq[string]$info.version -and [string]$f200Info.factorio_version-ceq'2.0') 'standalone identity discovery alternate F200 observer metadata differs'
  $archive=Join-Path (Resolve-Path -LiteralPath $ArchiveLibrary).Path 'mir-fixture-mir5-active-mods-observer_0.1.0.zip'
  Assert-Session ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToUpperInvariant()-ceq$ExpectedArchiveSha256.ToUpperInvariant()) 'standalone identity discovery A15 observer archive differs'
  $runtimeNames=@('data-final-fixes.lua','info.json');$prefix=$info.name+'_'+$info.version+'/'
  $zip=[IO.Compression.ZipFile]::OpenRead($archive)
  try {
    $entryNames=@($zip.Entries|ForEach-Object {$_.FullName})
    $expectedEntries=@($runtimeNames|ForEach-Object {$prefix+$_})
    Assert-Session ($entryNames.Count-eq$expectedEntries.Count-and ((@($entryNames|Sort-Object)-join '|')-ceq(@($expectedEntries|Sort-Object)-join '|'))) 'standalone identity discovery A15 observer archive members differ'
    foreach($name in $runtimeNames){
      $source=Join-Path $canonical $name;$entry=$zip.GetEntry($prefix+$name)
      Assert-Session ($null-ne$entry-and $entry.Length-eq(Get-Item -LiteralPath $source).Length) "standalone identity discovery A15 observer member differs: $name"
      $stream=$entry.Open();try{$entryHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
      Assert-Session ($entryHash-ceq(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToUpperInvariant()) "standalone identity discovery A15 observer bytes differ: $name"
    }
  } finally {$zip.Dispose()}
  $stage=Join-Path $OutputRoot 'standalone-identity-observer-source'
  Assert-Session (-not(Test-Path -LiteralPath $stage)) 'standalone identity discovery observer source stage already exists'
  $null=New-Item -ItemType Directory -Path $stage
  foreach($name in $runtimeNames){[IO.File]::Copy((Join-Path $canonical $name),(Join-Path $stage $name),$false)}
  $stageNames=@(Get-ChildItem -LiteralPath $stage -Recurse -File|ForEach-Object {[IO.Path]::GetRelativePath($stage,$_.FullName).Replace('\','/')})
  Assert-Session ($stageNames.Count-eq$runtimeNames.Count-and ((@($stageNames|Sort-Object)-join '|')-ceq(@($runtimeNames|Sort-Object)-join '|'))) 'standalone identity discovery observer projection members differ'
  foreach($name in $runtimeNames){Assert-Session ((Get-FileHash -LiteralPath (Join-Path $stage $name) -Algorithm SHA256).Hash.ToUpperInvariant()-ceq(Get-FileHash -LiteralPath (Join-Path $canonical $name) -Algorithm SHA256).Hash.ToUpperInvariant()) "standalone identity discovery observer projection bytes differ: $name"}
  Assert-MIRLibraryFixtureArchive -Archive $archive -SourceDirectory $stage
  return [pscustomobject]@{source=$stage;canonical_source=$canonical;archive=$archive;sha256=$ExpectedArchiveSha256.ToUpperInvariant();members=@($runtimeNames|ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $stage $_) -Algorithm SHA256).Hash.ToUpperInvariant()}});alternate_metadata='info-f200.json'}
}
function Resolve-StandaloneF210ApiConsumerSourceRevision {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $revision=@(& git -C $RepoRoot rev-parse --verify 'HEAD^{commit}')
  Assert-Session ($LASTEXITCODE-eq0-and$revision.Count-eq1-and$revision[0]-cmatch'^[0-9a-f]{40}$') 'standalone API consumer source revision differs'
  return [string]$revision[0]
}
function Get-StandaloneF210ApiConsumerRawGitMemberBytes {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$SourceRevision,
    [Parameter(Mandatory)][ValidateSet('mir-fixture-mir5-api-alpha','mir-fixture-mir5-api-beta')][string]$FixtureName,
    [Parameter(Mandatory)][string]$Member
  )
  $shortName=if($FixtureName-ceq'mir-fixture-mir5-api-alpha'){'api-alpha'}else{'api-beta'}
  $runtimeNames=if($shortName-ceq'api-alpha'){@('control.lua','data.lua','graphics/icon.png','info.json')}else{@('control.lua','data-final-fixes.lua','graphics/icon.png','info.json')}
  Assert-Session (@($runtimeNames)+@('info-f200.json')-ccontains$Member) "standalone API consumer member is not admitted: $FixtureName/$Member"
  $start=[Diagnostics.ProcessStartInfo]::new()
  $start.FileName='git';$start.UseShellExecute=$false;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  foreach($argument in @('-C',$RepoRoot,'show',($SourceRevision+':tests/fixtures/'+$shortName+'/'+$Member))){$null=$start.ArgumentList.Add($argument)}
  $process=[Diagnostics.Process]::new();$process.StartInfo=$start
  Assert-Session ($process.Start()) "standalone API consumer raw Git read did not start: $FixtureName/$Member"
  $bytes=[IO.MemoryStream]::new()
  try{
    $process.StandardOutput.BaseStream.CopyTo($bytes)
    $null=$process.StandardError.ReadToEnd()
    $process.WaitForExit()
    Assert-Session ($process.ExitCode-eq0) "standalone API consumer raw Git member differs: $FixtureName/$Member"
  } finally {$process.Dispose()}
  return ,$bytes.ToArray()
}
function New-StandaloneF210ApiConsumerSourceProjection {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$ArchiveLibrary,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][ValidateSet('mir-fixture-mir5-api-alpha','mir-fixture-mir5-api-beta')][string]$FixtureName,
    [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedArchiveSha256,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$SourceRevision
  )
  $shortName=if($FixtureName-ceq'mir-fixture-mir5-api-alpha'){'api-alpha'}else{'api-beta'}
  $runtimeNames=if($shortName-ceq'api-alpha'){@('control.lua','data.lua','graphics/icon.png','info.json')}else{@('control.lua','data-final-fixes.lua','graphics/icon.png','info.json')}
  $expectedCanonical=@($runtimeNames)+@('info-f200.json')
  $sourcePrefix='tests/fixtures/'+$shortName+'/'
  $canonicalPaths=@(& git -C $RepoRoot ls-tree -r --name-only $SourceRevision -- ('tests/fixtures/'+$shortName))
  Assert-Session ($LASTEXITCODE-eq0-and$canonicalPaths.Count-eq$expectedCanonical.Count) "standalone API canonical source members differ: $FixtureName"
  $canonicalNames=@($canonicalPaths|ForEach-Object {Assert-Session ($_.StartsWith($sourcePrefix,[StringComparison]::Ordinal)) "standalone API canonical source path differs: $FixtureName"; $_.Substring($sourcePrefix.Length)})
  Assert-Session ($canonicalNames.Count-eq$expectedCanonical.Count-and ((@($canonicalNames|Sort-Object)-join'|')-ceq(@($expectedCanonical|Sort-Object)-join'|'))) "standalone API canonical source members differ: $FixtureName"
  $info=[Text.Encoding]::UTF8.GetString((Get-StandaloneF210ApiConsumerRawGitMemberBytes -RepoRoot $RepoRoot -SourceRevision $SourceRevision -FixtureName $FixtureName -Member 'info.json'))|ConvertFrom-Json -AsHashtable
  $f200Info=[Text.Encoding]::UTF8.GetString((Get-StandaloneF210ApiConsumerRawGitMemberBytes -RepoRoot $RepoRoot -SourceRevision $SourceRevision -FixtureName $FixtureName -Member 'info-f200.json'))|ConvertFrom-Json -AsHashtable
  Assert-Session ([string]$info.name-ceq$FixtureName-and[string]$info.version-ceq'0.1.0'-and[string]$info.factorio_version-ceq'2.1') "standalone API canonical F210 metadata differs: $FixtureName"
  Assert-Session ([string]$f200Info.name-ceq$FixtureName-and[string]$f200Info.version-ceq'0.1.0'-and[string]$f200Info.factorio_version-ceq'2.0') "standalone API alternate F200 metadata differs: $FixtureName"
  $archive=Join-Path (Resolve-Path -LiteralPath $ArchiveLibrary).Path ($FixtureName+'_0.1.0.zip')
  Assert-Session ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToUpperInvariant()-ceq$ExpectedArchiveSha256.ToUpperInvariant()) "standalone API archive differs: $FixtureName"
  $stage=Join-Path $OutputRoot ('standalone-f210-'+$shortName+'-fixture-source')
  Assert-Session (-not(Test-Path -LiteralPath $stage)) "standalone API fixture stage already exists: $FixtureName"
  $null=New-Item -ItemType Directory -Path $stage
  foreach($name in $runtimeNames){
    $destination=Join-Path $stage $name
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination))|Out-Null
    [IO.File]::WriteAllBytes($destination,(Get-StandaloneF210ApiConsumerRawGitMemberBytes -RepoRoot $RepoRoot -SourceRevision $SourceRevision -FixtureName $FixtureName -Member $name))
  }
  $stageNames=@(Get-ChildItem -LiteralPath $stage -Recurse -File|ForEach-Object {[IO.Path]::GetRelativePath($stage,$_.FullName).Replace('\','/')})
  Assert-Session ($stageNames.Count-eq$runtimeNames.Count-and ((@($stageNames|Sort-Object)-join'|')-ceq(@($runtimeNames|Sort-Object)-join'|'))) "standalone API fixture projection members differ: $FixtureName"
  foreach($name in $runtimeNames){$expected=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData((Get-StandaloneF210ApiConsumerRawGitMemberBytes -RepoRoot $RepoRoot -SourceRevision $SourceRevision -FixtureName $FixtureName -Member $name)));Assert-Session ((Get-FileHash -LiteralPath (Join-Path $stage $name) -Algorithm SHA256).Hash.ToUpperInvariant()-ceq$expected) "standalone API fixture projection bytes differ: $FixtureName/$name"}
  Assert-MIRLibraryFixtureArchive -Archive $archive -SourceDirectory $stage
  return [pscustomobject]@{name=$FixtureName;source=$stage;source_revision=$SourceRevision;canonical_source=('tests/fixtures/'+$shortName);archive=$archive;sha256=$ExpectedArchiveSha256.ToUpperInvariant();members=@($runtimeNames|Sort-Object|ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $stage $_) -Algorithm SHA256).Hash.ToUpperInvariant()}});alternate_metadata='info-f200.json'}
}
function Get-StandaloneIdentityFixtureSources {
  param(
    [Parameter(Mandatory)][string[]]$Sources,
    [Parameter(Mandatory)][string]$LibraryFixtureSource,
    [Parameter(Mandatory)][string]$StagedLibraryFixtureSource,
    [Parameter(Mandatory)][string]$StagedObserverSource,
    [Parameter(Mandatory)][string]$RepoRoot,
    [AllowNull()][hashtable]$StagedApiConsumerSources=$null
  )
  $stagedApiConsumers=if($null-eq$StagedApiConsumerSources){@{}}else{$StagedApiConsumerSources}
  $canonicalObserver=(Resolve-Path -LiteralPath (Join-Path $RepoRoot 'tests/fixtures/active-mods-observer')).Path
  $canonicalInfo=Get-Content -LiteralPath (Join-Path $canonicalObserver 'info.json') -Raw|ConvertFrom-Json -AsHashtable
  Assert-Session ([string]$canonicalInfo.name-ceq'mir-fixture-mir5-active-mods-observer' -and [string]$canonicalInfo.version-ceq'0.1.0' -and [string]$canonicalInfo.factorio_version-ceq'2.1') 'standalone identity discovery canonical observer source differs'
  $library=(Resolve-Path -LiteralPath $LibraryFixtureSource).Path
  $staged=(Resolve-Path -LiteralPath $StagedLibraryFixtureSource).Path
  $result=[Collections.Generic.List[string]]::new();$libraryCount=0;$observerCount=0;$apiCounts=@{}
  foreach($name in @('mir-fixture-mir5-api-alpha','mir-fixture-mir5-api-beta')){$apiCounts[$name]=0}
  foreach($candidate in $Sources){
    $source=(Resolve-Path -LiteralPath $candidate).Path
    $info=Get-Content -LiteralPath (Join-Path $source 'info.json') -Raw|ConvertFrom-Json -AsHashtable
    if([string]$info.name-ceq'mir-fixture-mir5-library-multiplayer'){
      Assert-Session ($source-ieq$library) 'standalone identity discovery Library source differs from its canonical template'
      $libraryCount++;$result.Add($staged)
    }elseif([string]$info.name-ceq'mir-fixture-mir5-active-mods-observer'){
      Assert-Session ($source-ieq$canonicalObserver) 'standalone identity discovery observer source differs from its canonical source'
      $observerCount++;$result.Add((Resolve-Path -LiteralPath $StagedObserverSource).Path)
    }elseif($apiCounts.ContainsKey([string]$info.name)){
      $name=[string]$info.name
      Assert-Session ($stagedApiConsumers.ContainsKey($name)) "standalone API consumer source is not admitted: $name"
      $stagedApiSource=$stagedApiConsumers[$name]
      Assert-Session ($stagedApiSource -is [string] -and -not[string]::IsNullOrWhiteSpace($stagedApiSource)) "standalone API consumer projection path differs: $name"
      $canonicalApi=(Resolve-Path -LiteralPath (Join-Path $RepoRoot ('tests/fixtures/'+$(if($name-ceq'mir-fixture-mir5-api-alpha'){'api-alpha'}else{'api-beta'})))).Path
      Assert-Session ($source-ieq$canonicalApi) "standalone API consumer source differs from its canonical template: $name"
      $apiCounts[$name]++
      $result.Add((Resolve-Path -LiteralPath $stagedApiSource).Path)
    }else{$result.Add($source)}
  }
  Assert-Session ($libraryCount-eq1) 'standalone identity discovery requires one canonical Library fixture source'
  Assert-Session ($observerCount -le 1) 'standalone identity discovery observer source is duplicated'
  $stagedObserver=(Resolve-Path -LiteralPath $StagedObserverSource).Path
  if($observerCount-eq0){$result.Add($stagedObserver)}
  $actualObserver=@($result|Where-Object {$_-ieq$stagedObserver})
  Assert-Session ($actualObserver.Count-eq1) 'standalone identity discovery requires one verified canonical observer source'
  foreach($name in @($stagedApiConsumers.Keys)){
    Assert-Session ($apiCounts.ContainsKey([string]$name)-and$apiCounts[[string]$name]-eq1) "standalone API consumer source count differs: $name"
  }
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
$standaloneObserver=$null;$standaloneLibraryFixture=$null
$standaloneApiConsumerFixtures=@{}
$standaloneApiConsumerSources=@{}
$apiConsumerSourceRevision=$null
if($StandaloneIdentityDiscovery){
  # The checked-in functional profile is a template only.  The actual
  # environmental packet is assembled below from the standalone engine, C563,
  # A15 and the staged 0.1.1 fixture; it never relabels the FE4/2E profile.
  $null=Assert-MultiplayerFixtureSelection -Selection $selection -EngineSha256 'FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060' -FixtureCase 'library-multiplayer'
  $discoveryFixture=New-StandaloneIdentityFixtureStage -Sources $FixtureSources -OutputRoot $output
  $discoveryObserver=New-StandaloneIdentityObserverSourceProjection -RepoRoot $repo -ArchiveLibrary $library -OutputRoot $output -ExpectedArchiveSha256 'A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0'
  $fixtureSourcesForRun=Get-StandaloneIdentityFixtureSources -Sources $FixtureSources -LibraryFixtureSource (Join-Path $repo 'tests/fixtures/library-multiplayer') -StagedLibraryFixtureSource $discoveryFixture.source -StagedObserverSource $discoveryObserver.source -RepoRoot $repo
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
$target=Assert-MultiplayerFixtureSelection -Selection $selection -EngineSha256 (Get-FileHash -LiteralPath $engine).Hash -FixtureCase $FixtureCase -ExpectedMIRArchiveSha256 $ExpectedMIRArchiveSha256 -SessionExpectedPeakMemoryMiB $SessionExpectedPeakMemoryMiB -StandaloneIdentityDiscovery:$StandaloneIdentityDiscovery
$standaloneF210=($target.PSObject.Properties['standalone_f210'] -and $target.standalone_f210 -eq $true)
$spaceAgeLibrary=($target.PSObject.Properties['space_age_library'] -and $target.space_age_library -eq $true)
$privateCreditChecks=($target.PSObject.Properties['private_credit_checks'] -and $target.private_credit_checks -eq $true)
if($standaloneF210){
  # Standalone Base and Space Age retain their 0.1.0/0.2.0 metadata; only the
  # two explicit private-credit selections stage the common 0.3.0 metadata.
  $standaloneLibraryFixture=New-StandaloneF210LibraryFixtureSourceProjection -RepoRoot $repo -OutputRoot $output -SpaceAgeLibrary:$spaceAgeLibrary -PrivateCreditChecks:$privateCreditChecks
  $standaloneObserver=New-StandaloneIdentityObserverSourceProjection -RepoRoot $repo -ArchiveLibrary $library -OutputRoot $output -ExpectedArchiveSha256 ([string]$target.observer_sha256)
  if($target.PSObject.Properties['api_client_consumers']-and$target.api_client_consumers-eq$true){
    $apiConsumerSourceRevision=Resolve-StandaloneF210ApiConsumerSourceRevision -RepoRoot $repo
    foreach($name in @('mir-fixture-mir5-api-alpha','mir-fixture-mir5-api-beta')){
      $archiveName=$name+'_0.1.0.zip'
      $standaloneApiConsumerFixtures[$name]=New-StandaloneF210ApiConsumerSourceProjection -RepoRoot $repo -ArchiveLibrary $library -OutputRoot $output -FixtureName $name -ExpectedArchiveSha256 ([string]$target.api_consumer_archive_sha256[$archiveName]) -SourceRevision $apiConsumerSourceRevision
      $standaloneApiConsumerSources[$name]=[string]$standaloneApiConsumerFixtures[$name].source
    }
  }
  $canonicalLibrary=Join-Path $repo 'tests/fixtures/library-multiplayer'
  $fixtureSourcesForRun=Get-StandaloneIdentityFixtureSources -Sources $FixtureSources -LibraryFixtureSource $canonicalLibrary -StagedLibraryFixtureSource $standaloneLibraryFixture.source -StagedObserverSource $standaloneObserver.source -RepoRoot $repo -StagedApiConsumerSources $standaloneApiConsumerSources
}
# The normal standalone target remains the ordinary two-client Library
# contract.  Only the explicitly environmental discovery route needs its
# distinct synthetic labels.
$standaloneClientNames=$StandaloneIdentityDiscovery
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
  standalone_identity_discovery=if($StandaloneIdentityDiscovery){[ordered]@{fixture_source=$discoveryFixture.source;fixture_archive_sha256=[string]$selection.archive_sha256['mir-fixture-mir5-library-multiplayer_0.1.1.zip'];observer_source=$discoveryObserver.source;observer_canonical_source=$discoveryObserver.canonical_source;observer_archive_sha256=$discoveryObserver.sha256;observer_members=$discoveryObserver.members;observer_alternate_metadata=$discoveryObserver.alternate_metadata;environmental_only=$true}}else{$null}
  standalone_f210=if($standaloneF210){[ordered]@{fixture_source=$standaloneLibraryFixture.source;fixture_canonical_source=$standaloneLibraryFixture.canonical_source;fixture_members=$standaloneLibraryFixture.members;fixture_source_metadata=$standaloneLibraryFixture.source_metadata;fixture_excluded_canonical_members=$standaloneLibraryFixture.excluded_canonical_members;observer_source=$standaloneObserver.source;observer_canonical_source=$standaloneObserver.canonical_source;observer_archive_sha256=$standaloneObserver.sha256;observer_members=$standaloneObserver.members;observer_alternate_metadata=$standaloneObserver.alternate_metadata;api_consumer_source_revision=$apiConsumerSourceRevision;private_credit_checks=$privateCreditChecks;steam_identity=$false}}else{$null}
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
    $name=if($standaloneClientNames){'standalone-'+$locale}elseif($locale -ceq 'en'){'MIR5English'}else{'MIR5Deutsch'}
    # Isolated disposable identities contain no online token or personal data.
    # Discovery alone uses the bounded synthetic label for its actual join
    # marker; every route still keeps its token and write-data isolated.
    $player=@{'service-username'=$name;'service-token'='';'last-played-version'=@{game_version=$target.base;build_version=$target.build_version;build_mode='full';platform='win64'}}
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
  $clientGraphics=@(if($FixtureCase-ceq'scripted-effects-multiplayer' -or $spaceAgeLibrary){'--force-graphics-preset';'low';'--video-memory-usage';'low'})
  foreach($client in $clients){Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments (@('--config',$client.config,'--mod-directory',$library,'--disable-audio','--no-log-rotation','--window-size','1280x720','--mp-connect',('127.0.0.1:'+ $serverPort),'--port',[string]$client.port)+$clientGraphics)}
  $screenshots=@(
    if($FixtureCase-ceq'library-multiplayer' -and -not $StandaloneIdentityDiscovery){
      foreach($client in $clients){foreach($stage in @('availability','initial','settled','rejoin','restart')){Join-Path $client.write_data ('script-output/mir5-library-multiplayer/'+$stage+'-*.png')}}
    }elseif($FixtureCase-ceq'library-paired-browser'){
      foreach($client in $clients){foreach($stage in @('first-open','first-open-settled','search','refresh','reopen','reopen-settled')){Join-Path $client.write_data ('script-output/mir5-library-paired-browser/'+$stage+'-*.png')}}
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
    if($spaceAgeLibrary){$spec.space_age_library=$true}
    if($privateCreditChecks){$spec.private_credit_checks=$true}
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
  if(-not $StandaloneIdentityDiscovery -and -not $standaloneF210){$processArguments.FactorioSteamIdentity=$true}
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
