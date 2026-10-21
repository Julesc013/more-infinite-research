# MIR4-CANONICAL-EXECUTABLE-TEST
<#!
.SYNOPSIS
Runs one fresh, exact F210/Krastorio2/K2SO Imersite-continuation create and
single reload. Supply a portable exact input profile or the historical V5
observation lock. Neither input contract grants gameplay acceptance.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$CandidateZip,
  [Parameter(Mandatory)][string]$SourceMaterializationPath,
  [ValidatePattern('^4[.](?:0|[1-9][0-9]{0,4})[.](?:0|[1-9][0-9]?)$')][string]$SourceVersion = '4.2.1',
  [string]$V5ObservationResultPath = '',
  [string]$InputProfilePath = '',
  [string]$RepoRoot = '',
  [string]$OutputRoot = 'build/p/k2-213-imersite-continuation',
  [string[]]$LocalModLibraryDirs = @(),
  [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB = 0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB = 120,
  [ValidateRange(0,300)][int]$AdmissionWaitSeconds = 0,
  [switch]$PreflightOnly,
  [ValidateRange(1,180)][int]$CreateTimeoutSeconds = 90,
  [ValidateRange(1,180)][int]$ReloadTimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/ImmutableInputStaging.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/NativeProbeResources.ps1')
if ($AdmissionWaitSeconds -gt 0) {
  . (Join-Path $RepoRoot 'tools/lib/validation/DirectLibraryStartupMeasurement.ps1')
}

function Fail-K2213 { param([string]$Code) throw "[mir42-k2-213-imersite] $Code" }
function Assert-K2213 { param([bool]$Condition,[string]$Code) if (-not $Condition) { Fail-K2213 $Code } }
function Get-K2213Sha256 { param([Parameter(Mandatory)][string]$Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
function Get-K2213Property { param($Object,[string]$Name,$Default=$null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}
function Read-K2213CurrentCandidate([string]$Archive,[string]$ReceiptPath,
  [ValidatePattern('^4[.](?:0|[1-9][0-9]{0,4})[.](?:0|[1-9][0-9]?)$')][string]$SourceVersion='4.2.1') {
  Read-MIRNativeProbeF210CurrentCandidate -Repository $RepoRoot -Archive $Archive -ReceiptPath $ReceiptPath -SourceVersion $SourceVersion
}
function Read-K2213DependencyInputs($Observation,[Collections.IDictionary]$ExpectedDependencies,[string[]]$Libraries,[string]$ObservationPath) {
  $lockEntries=@($Observation.staged_inputs)
  Assert-K2213 ($lockEntries.Count -ge $ExpectedDependencies.Count) 'v5-staged-input-count'
  $expectedHashes=[ordered]@{};$lockedPaths=[ordered]@{}
  foreach($fileName in $ExpectedDependencies.Keys) {
    $matches=@($lockEntries|Where-Object {[IO.Path]::GetFileName([string]$_.source_path) -ceq $fileName})
    Assert-K2213 ($matches.Count -eq 1) "v5-dependency-lock:$fileName"
    $entry=$matches[0]
    Assert-K2213 ([bool]$entry.source_match -and [bool]$entry.stage_match -and ([string]$entry.sha256 -cmatch '^[0-9A-F]{64}$')) "v5-dependency-lock-integrity:$fileName"
    $expectedHashes[$fileName]=[string]$entry.sha256
    $lockedPaths[$fileName]=[string]$entry.source_path
  }
  # Historical paths remain custody text. Resolve only the explicit flat
  # libraries; never restore or walk the retired V5 profile directories.
  $resolved=Resolve-MIRNativeProbeDependencyInputs -ExpectedArchives $expectedHashes -LocalModLibraryDirs $Libraries
  $inputs=@()
  foreach($fileName in $ExpectedDependencies.Keys) {
    $source=[string]$resolved[$fileName].source_path
    Assert-K2213ArchiveIdentity -Path $source -ExpectedName $ExpectedDependencies[$fileName][0] -ExpectedVersion $ExpectedDependencies[$fileName][1] -ExpectedSha256 $expectedHashes[$fileName]
    $inputs += [ordered]@{source_path=$source;file_name=$fileName;expected_sha256=$expectedHashes[$fileName];role='dependency-mod';identity=[ordered]@{name=$ExpectedDependencies[$fileName][0];version=$ExpectedDependencies[$fileName][1];archive=$fileName};provenance=[ordered]@{kind='verified-local-library-with-v5-dependency-lock';v5_result_sha256=Get-K2213Sha256 $ObservationPath;historical_source_path=$lockedPaths[$fileName]};immutable=$true}
  }
  return $inputs
}
function Get-K2213ProfileExternalDependencies {
  param($Profile,[string]$Code='current-profile')
  Assert-K2213 ($null -ne $Profile -and @($Profile.mods).Count -gt 0) "$Code-mods"
  Assert-K2213 ($null -ne $Profile.archive_sha256) "$Code-archives"
  $excluded=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($name in @('base','elevated-rails','quality','recycler','space-age','more-infinite-research','mir-fixture-assert-k2-213-imersite-continuation')){$null=$excluded.Add($name)}
  $dependencies=[ordered]@{}
  $versions=[ordered]@{}
  foreach($row in @($Profile.mods)){
    $name=[string](Get-K2213Property $row 'name' '')
    $version=[string](Get-K2213Property $row 'version' '')
    Assert-K2213 ($name -cmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$' -and $version -cmatch '^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$') "$Code-mod-identity:$name"
    if($excluded.Contains($name)){continue}
    $enabled=Get-K2213Property $row 'enabled' $false
    Assert-K2213 ($enabled -is [bool] -and $enabled) "$Code-mod-enabled:$name"
    Assert-K2213 (-not $versions.Contains($name)) "$Code-mod-duplicate:$name"
    $fileName=$name+'_'+$version+'.zip'
    $hash=[string](Get-K2213Property $Profile.archive_sha256 $fileName '')
    Assert-K2213 ($hash -cmatch '^[0-9A-F]{64}$') "$Code-archive-hash:$fileName"
    $versions[$name]=$version
    $dependencies[$fileName]=@($name,$version)
  }
  foreach($name in @('Krastorio2','Krastorio2-spaced-out')){Assert-K2213 ($versions.Contains($name)) "$Code-required-mod:$name"}
  $archiveProperties=@($Profile.archive_sha256.PSObject.Properties)
  Assert-K2213 ($archiveProperties.Count -eq $dependencies.Count) "$Code-archive-count"
  foreach($property in $archiveProperties){
    Assert-K2213 ($dependencies.Contains($property.Name) -and ([string]$property.Value -cmatch '^[0-9A-F]{64}$')) "$Code-archive-identity:$($property.Name)"
  }
  return [pscustomobject]@{dependencies=$dependencies;versions=$versions}
}
function Read-K2213CurrentFixtureRegistration {
  param([string]$Path=(Join-Path $RepoRoot '.mir/fixtures.yml'))
  $text=[IO.File]::ReadAllText($path)
  $entry=[regex]::Match($text,'(?ms)^  k2-213-imersite-continuation:\s*\r?\n(?<body>.*?)(?=^  [A-Za-z0-9][A-Za-z0-9_-]*:\s*\r?\n|\z)')
  Assert-K2213 $entry.Success 'registered-fixture-absent'
  $body=$entry.Groups['body'].Value
  $fields=[ordered]@{}
  foreach($name in @('current_input_profile','current_fixture_version','current_candidate_version','current_engine_version')){
    $matches=[regex]::Matches($body,'(?m)^    '+$name+': (?<value>"[^"\r\n]+"|[A-Za-z0-9_./-]+)\s*\r?$')
    Assert-K2213 ($matches.Count-eq1) ('registered-fixture-current-field:'+$name)
    $fields[$name]=$matches[0].Groups['value'].Value.Trim('"')
  }
  Assert-K2213 ($fields.current_input_profile-cmatch'^fixtures/run-profiles/[A-Za-z0-9_.-]+[.]json$') 'registered-fixture-current-profile-path'
  Assert-K2213 ($fields.current_fixture_version-cmatch'^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$') 'registered-fixture-current-version'
  Assert-K2213 ($fields.current_engine_version-cmatch'^2[.]1[.](?:0|[1-9][0-9]*)$'-and[version]$fields.current_engine_version-ge[version]'2.1.20') 'registered-fixture-current-engine'
  $versions=[regex]::Matches($body,'(?m)^    candidate_versions: (?<value>\[[^\r\n]+\])\r?$')
  Assert-K2213 ($versions.Count-eq1) 'registered-fixture-candidate-versions'
  $candidates=@($versions[0].Groups['value'].Value|ConvertFrom-Json)
  Assert-K2213 ($candidates-ccontains$fields.current_candidate_version-and$body.Contains('      - '+$fields.current_input_profile,[StringComparison]::Ordinal)) 'registered-fixture-current-membership'
  $profile=Read-K2213Json -Path (Join-Path $RepoRoot $fields.current_input_profile) -Code 'registered-fixture-current-profile'
  Assert-K2213 ($profile.schema -eq 1 -and $profile.target -ceq 'f210' -and $profile.factorio_line -ceq '2.1' -and $profile.settings_mode -ceq 'Defaults') 'registered-fixture-current-profile-shape'
  Assert-K2213 ($profile.engine_version-ceq$fields.current_engine_version) 'registered-fixture-current-engine-profile'
  foreach($field in @('engine_sha256','runtime_api_sha256')){Assert-K2213 ([string]$profile.$field -cmatch '^[0-9A-F]{64}$') "registered-fixture-current-profile-hash:$field"}
  $external=Get-K2213ProfileExternalDependencies -Profile $profile -Code 'registered-fixture-current-profile'
  return [pscustomobject]@{fixture_version=$fields.current_fixture_version;mir_version=$fields.current_candidate_version;input_profile=$fields.current_input_profile;retained=$false;current_registration=$true;engine_versions=@($fields.current_engine_version);external_dependencies=$external.dependencies;external_versions=$external.versions}
}
function Get-K2213SelectedFixtureProfile {
  param([ValidatePattern('^4[.](?:0|[1-9][0-9]{0,4})[.](?:0|[1-9][0-9]?)$')][string]$SourceVersion='4.2.1')
  # These are retained fixture identities, not an allow-list for new releases.
  $profiles=[ordered]@{
    '4.2.1'=[ordered]@{fixture_version='0.1.4';mir_version='4.2.21001';input_profile='';retained=$true;external_versions=[ordered]@{Krastorio2='2.1.3';'Krastorio2-spaced-out'='2.0.13'}}
    '4.2.2'=[ordered]@{fixture_version='0.1.4';mir_version='4.2.21002';input_profile='';retained=$true;external_versions=[ordered]@{Krastorio2='2.1.3';'Krastorio2-spaced-out'='2.0.13'}}
    '4.4.0'=[ordered]@{fixture_version='0.1.5';mir_version='4.4.21000';input_profile='fixtures/run-profiles/k2-213-imersite-f210-440.json';retained=$false;external_versions=[ordered]@{Krastorio2='2.1.3';'Krastorio2-spaced-out'='2.0.13'}}
    '4.6.0'=[ordered]@{fixture_version='0.1.6';mir_version='4.6.21000';input_profile='fixtures/run-profiles/k2-213-imersite-f210-460.json';retained=$false;external_versions=[ordered]@{Krastorio2='2.1.3';'Krastorio2-spaced-out'='2.0.13'}}
  }
  if($profiles.Contains($SourceVersion)){
    $profile=$profiles[$SourceVersion];$profile.current_registration=$false;$profile.engine_versions=@('2.1.20','2.1.21')
    return [pscustomobject]$profile
  }
  $current=Read-K2213CurrentFixtureRegistration
  $identity=Resolve-MIR4CanonicalPackageIdentity -RepoRoot $RepoRoot -Target f210 -SourceVersion $SourceVersion
  Assert-K2213 ($identity.distribution_version-ceq$current.mir_version) 'registered-fixture-current-candidate'
  return $current
}
function Get-K2213ExpectedDependencies {
  param([ValidatePattern('^4[.](?:0|[1-9][0-9]{0,4})[.](?:0|[1-9][0-9]?)$')][string]$SourceVersion='4.2.1')
  $profile=Get-K2213SelectedFixtureProfile -SourceVersion $SourceVersion
  if([bool]$profile.current_registration){return $profile.external_dependencies}
  return [ordered]@{
    'flib_0.17.2.zip'=@('flib','0.17.2')
    'k2so-assets_1.0.7.zip'=@('k2so-assets','1.0.7')
    'Krastorio2_2.1.3.zip'=@('Krastorio2','2.1.3')
    'Krastorio2-spaced-out_2.0.13.zip'=@('Krastorio2-spaced-out','2.0.13')
    'Krastorio2Assets_2.1.0.zip'=@('Krastorio2Assets','2.1.0')
    'Krastorio2MenuSimulations_2.1.0.zip'=@('Krastorio2MenuSimulations','2.1.0')
    'xy-k2so-enhancements-nulls-fork_0.8.3.zip'=@('xy-k2so-enhancements-nulls-fork','0.8.3')
  }
}
function Assert-K2213SelectedInputMode {
  param([ValidatePattern('^4[.](?:0|[1-9][0-9]{0,4})[.](?:0|[1-9][0-9]?)$')][string]$SourceVersion,[string]$V5Path,[string]$ProfilePath)
  Assert-K2213 (([bool]$V5Path) -xor ([bool]$ProfilePath)) 'supply-one-input-profile-or-historical-observation'
  if(-not (Get-K2213SelectedFixtureProfile -SourceVersion $SourceVersion).retained){
    Assert-K2213 ([bool]$ProfilePath -and -not [bool]$V5Path) 'current-440-requires-explicit-profile'
  }
}
function New-K2213SelectedFixture {
  param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Run,
    [ValidatePattern('^4[.](?:0|[1-9][0-9]{0,4})[.](?:0|[1-9][0-9]?)$')][string]$SourceVersion,
    [Parameter(Mandatory)][string]$SelectedMIRVersion)
  $profile=Get-K2213SelectedFixtureProfile -SourceVersion $SourceVersion
  Assert-K2213 ($SelectedMIRVersion-ceq[string]$profile.mir_version) 'selected-fixture-candidate-version'
  if([bool]$profile.retained){return $Source}
  $selected=Join-Path $Run 'fixture-source'
  [IO.Directory]::CreateDirectory($selected)|Out-Null
  $info=Read-K2213Json -Path (Join-Path $Source 'info.json') -Code 'fixture-info'
  Assert-K2213 ([string]$info.version-ceq'0.1.4') 'fixture-template-version'
  $info.version=[string]$profile.fixture_version
  $info.dependencies=@('base >= 2.1.20',('Krastorio2 = '+[string]$profile.external_versions['Krastorio2']),('Krastorio2-spaced-out = '+[string]$profile.external_versions['Krastorio2-spaced-out']),('more-infinite-research = '+[string]$profile.mir_version))
  [IO.File]::WriteAllText((Join-Path $selected 'info.json'),($info|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
  $settingsTemplate=Join-Path $Source 'settings-updates.lua'
  Assert-K2213 (Test-Path -LiteralPath $settingsTemplate -PathType Leaf) 'fixture-template-settings'
  [IO.File]::WriteAllBytes((Join-Path $selected 'settings-updates.lua'),[IO.File]::ReadAllBytes($settingsTemplate))
  $replacements=[ordered]@{
    'data-final-fixes.lua'=@('mods["more-infinite-research"] ~= "4.2.21001"`n    and mods["more-infinite-research"] ~= "4.2.21002"',('mods["more-infinite-research"] ~= "'+[string]$profile.mir_version+'"'))
    'control.lua'=@('script.active_mods["more-infinite-research"] ~= "4.2.21001"`n      and script.active_mods["more-infinite-research"] ~= "4.2.21002"',('script.active_mods["more-infinite-research"] ~= "'+[string]$profile.mir_version+'"'))
  }
  foreach($entry in $replacements.GetEnumerator()){
    # Windows checkouts may supply CRLF. Normalize only the new selected
    # fixture; the retained template and its raw-hash provenance stay intact.
    $text=[IO.File]::ReadAllText((Join-Path $Source $entry.Key)).Replace("`r`n","`n")
    $from=$entry.Value[0].Replace('`n',"`n")
    Assert-K2213 ($text.Contains($from,[StringComparison]::Ordinal)) "fixture-specialization-anchor:$($entry.Key)"
    $text=$text.Replace($from,$entry.Value[1])
    if($profile.current_registration){
      $prefix=if($entry.Key-ceq'data-final-fixes.lua'){'mods'}else{'script.active_mods'}
      $oldEngine=$prefix+'.base ~= "2.1.20" and '+$prefix+'.base ~= "2.1.21"'
      $newEngine=$prefix+'.base ~= "'+[string]$profile.engine_versions[0]+'"'
      Assert-K2213 ($text.Contains($oldEngine,[StringComparison]::Ordinal)) ("fixture-engine-specialization-anchor:"+$entry.Key)
      $text=$text.Replace($oldEngine,$newEngine)
      foreach($pair in @(
        [ordered]@{name='Krastorio2';old='Krastorio2 = "2.1.3"';format={param($version) 'Krastorio2 = "'+$version+'"'}},
        [ordered]@{name='Krastorio2-spaced-out';old='["Krastorio2-spaced-out"] = "2.0.13"';format={param($version) '["Krastorio2-spaced-out"] = "'+$version+'"'}}
      )){
        $oldExternal=[string]$pair.old
        $newExternal=& $pair.format ([string]$profile.external_versions[$pair.name])
        $matches=[regex]::Matches($text,[regex]::Escape($oldExternal)).Count
        Assert-K2213 ($matches -eq 1) ("fixture-external-specialization-anchor:"+$entry.Key+':'+$pair.name)
        $text=$text.Replace($oldExternal,$newExternal)
      }
      if($entry.Key-ceq'control.lua'){
        # The retained template remains the historical K2 2.1.3 fixture. The
        # current 2.1.4/K2SO selection earns only the visible finite levels,
        # one native crystal level, and the visible continuation below. Hidden
        # migration-credit holders must stay unresearched or they add .04.
        $earnedStateAnchor=@'
  force.research_all_technologies()
  local legacy = force.technologies[legacy_name]
  local stage = force.technologies[continuation_name]
  if not legacy or not stage then fail("required Imersite staged technology absent") end
'@
        $earnedStateAnchor=$earnedStateAnchor.TrimEnd("`r","`n")
        $earnedState=@'
  local legacy = force.technologies[legacy_name]
  local stage = force.technologies[continuation_name]
  local native = force.technologies["kr-imersite-productivity"]
  local early_holder = force.technologies["mir-k2-imersite-staged-state-1"]
  local continuation_holder = force.technologies["mir-k2-imersite-continuation-state-4"]
  if not legacy or not stage or not native or not early_holder or not continuation_holder then
    fail("required current Imersite technology absent")
  end
  local function research_prerequisites(technology)
    for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  end
  research_prerequisites(legacy)
  research_prerequisites(native)
  research_prerequisites(stage)
  legacy.level = 3
  legacy.researched = true
  native.researched = true
  force.reset_technology_effects()
  if legacy.level ~= 3 or legacy.prototype.max_level ~= 3 or not legacy.researched then
    fail("could not complete exact finite Imersite levels")
  end
  assert_close("finite Imersite powder bonus", force.recipes[powder_recipe].productivity_bonus, 0.06)
  assert_close("native crystal bonus", force.recipes[crystal_recipe].productivity_bonus, 0.1)
  if early_holder.researched or continuation_holder.researched then
    fail("migration-credit holders must remain unearned")
  end
'@
        $matches=[regex]::Matches($text,[regex]::Escape($earnedStateAnchor)).Count
        Assert-K2213 ($matches -eq 1) 'fixture-current-earned-state-anchor'
        $text=$text.Replace($earnedStateAnchor,$earnedState.TrimEnd("`r","`n"))
        $continuationAnchor=@'
  stage.level = 5
  force.reset_technology_effects()
'@
        $continuationAnchor=$continuationAnchor.TrimEnd("`r","`n")
        $continuationSetup=@'
  stage.level = 5
  force.reset_technology_effects()
  force.recipes[powder_recipe].enabled = true
  if not force.recipes[powder_recipe].enabled then
    fail("could not enable Imersite powder production witness")
  end
  assert_close("visible continuation powder bonus", force.recipes[powder_recipe].productivity_bonus, 0.08)
  if early_holder.researched or continuation_holder.researched then
    fail("migration-credit holders must remain unearned after continuation setup")
  end
'@
        $continuationSetup=$continuationSetup.TrimEnd("`r","`n")
        $matches=[regex]::Matches($text,[regex]::Escape($continuationAnchor)).Count
        Assert-K2213 ($matches -eq 1) 'fixture-current-continuation-state-anchor'
        $text=$text.Replace($continuationAnchor,$continuationSetup)
      }
    }
    Assert-K2213 ($text.Contains([string]$profile.mir_version,[StringComparison]::Ordinal)-and-not$text.Contains('4.2.21001',[StringComparison]::Ordinal)-and-not$text.Contains('4.2.21002',[StringComparison]::Ordinal)) "fixture-specialization-result:$($entry.Key)"
    [IO.File]::WriteAllText((Join-Path $selected $entry.Key),$text,[Text.UTF8Encoding]::new($false))
  }
  return $selected
}
function Read-K2213ProfileInputs {
  param([string]$Path,[Collections.IDictionary]$ExpectedDependencies,[string[]]$Libraries,
    [ValidatePattern('^4[.](?:0|[1-9][0-9]{0,4})[.](?:0|[1-9][0-9]?)$')][string]$SourceVersion='4.2.1')
  $profile=Read-K2213Json -Path $Path -Code 'input-profile'
  Assert-K2213 ($profile.schema -eq 1 -and $profile.target -ceq 'f210' -and $profile.factorio_line -ceq '2.1') 'input-profile-schema-target'
  $fixtureProfile=Get-K2213SelectedFixtureProfile -SourceVersion $SourceVersion
  Assert-K2213 ($profile.engine_version -cin @($fixtureProfile.engine_versions)) 'input-profile-engine-version'
  foreach($field in @('engine_sha256','runtime_api_sha256')){Assert-K2213 ([string]$profile.$field -cmatch '^[0-9A-F]{64}$') "input-profile-hash:$field"}
  Assert-K2213 ($profile.settings_mode -ceq 'Defaults') 'input-profile-settings'
  $expected=[ordered]@{}
  foreach($name in @('base','elevated-rails','quality','recycler','space-age')){$expected[$name]=[string]$profile.engine_version}
  foreach($fileName in $ExpectedDependencies.Keys){$expected[$ExpectedDependencies[$fileName][0]]=$ExpectedDependencies[$fileName][1]}
  $identity=Resolve-MIR4CanonicalPackageIdentity -RepoRoot $RepoRoot -Target f210 -SourceVersion $SourceVersion
  Assert-K2213 ([string]$identity.distribution_version-ceq[string]$fixtureProfile.mir_version) 'input-profile-candidate-identity'
  $expected['more-infinite-research']=$identity.distribution_version
  $expected['mir-fixture-assert-k2-213-imersite-continuation']=[string]$fixtureProfile.fixture_version
  Assert-K2213 (@($profile.mods).Count -eq $expected.Count) 'input-profile-selection-count'
  foreach($name in $expected.Keys){
    $rows=@($profile.mods|Where-Object {$_.name -ceq $name})
    Assert-K2213 ($rows.Count -eq 1 -and $rows[0].enabled -is [bool] -and $rows[0].enabled -and $rows[0].version -ceq $expected[$name]) "input-profile-selection:$name"
  }
  $hashes=[ordered]@{}
  Assert-K2213 (@($profile.archive_sha256.PSObject.Properties).Count -eq $ExpectedDependencies.Count) 'input-profile-archive-count'
  foreach($fileName in $ExpectedDependencies.Keys){
    $hash=[string](Get-K2213Property $profile.archive_sha256 $fileName '')
    Assert-K2213 ($hash -cmatch '^[0-9A-F]{64}$') "input-profile-archive-hash:$fileName"
    $hashes[$fileName]=$hash
  }
  $resolved=Resolve-MIRNativeProbeDependencyInputs -ExpectedArchives $hashes -LocalModLibraryDirs $Libraries
  $inputs=@(foreach($fileName in $ExpectedDependencies.Keys){
    $source=[string]$resolved[$fileName].source_path
    Assert-K2213ArchiveIdentity -Path $source -ExpectedName $ExpectedDependencies[$fileName][0] -ExpectedVersion $ExpectedDependencies[$fileName][1] -ExpectedSha256 $hashes[$fileName]
    [ordered]@{source_path=$source;file_name=$fileName;expected_sha256=$hashes[$fileName];role='dependency-mod';identity=@{name=$ExpectedDependencies[$fileName][0];version=$ExpectedDependencies[$fileName][1]};provenance=@{kind='portable-exact-input-profile';profile_sha256=Get-K2213Sha256 $Path};immutable=$true}
  })
  return [pscustomobject]@{profile=$profile;inputs=$inputs;fixture_profile=$fixtureProfile}
}
function Invoke-K2213NativeActor {
  param([ValidateSet('engine-version','create','reload')][string]$Phase,[string]$FactorioBin,[string[]]$Arguments,[int]$TimeoutSeconds)
  $parameters=@{Context=$resources;FilePath=$FactorioBin;Arguments=$Arguments;TimeoutSeconds=$TimeoutSeconds}
  if($AdmissionWaitSeconds -gt 0){
    $parameters.AdmissionWaitSeconds=$AdmissionWaitSeconds
    $parameters.AdmissionPhase=$Phase
  }
  $actor=Invoke-MIRNativeProbeFactorioProcess @parameters
  if($AdmissionWaitSeconds -gt 0){
    $wait=Get-K2213Property $actor 'admission_wait'
    Assert-K2213 ($null-ne$wait-and[string]$wait.phase-ceq$Phase) 'native-actor-admission-receipt'
    $admissionWaits.Add($wait)
  }
  return $actor
}
function Invoke-MIRCompatFactorioProcess {
  param([string]$FactorioBin,[object[]]$ArgumentList,[string]$StdoutPath,[string]$StderrPath,[int]$TimeoutSeconds,$LibraryActivation)
  # Preserve the existing create/reload collector and its exact oracles,
  # while charging their native actors to one owned row over the active library.
  Assert-MIRLibraryLaunch -Activation $LibraryActivation -FactorioBin $FactorioBin -Arguments ([string[]]$ArgumentList)
  # This scenario's one reload also measures real crusher output. Preserve the
  # shared collector's one-tick default for every other native consumer.
  $tickIndex=[Array]::IndexOf($ArgumentList,'--benchmark-ticks')
  if($tickIndex-ge0){$ArgumentList[$tickIndex+1]='25000'}
  Assert-K2213 ($tickIndex-ge0-or$ArgumentList-contains'--create') 'native-actor-phase'
  $phase=if($tickIndex-ge0){'reload'}else{'create'}
  $actor=Invoke-K2213NativeActor -Phase $phase -FactorioBin $FactorioBin -Arguments ([string[]]$ArgumentList) -TimeoutSeconds $TimeoutSeconds
  Copy-Item -LiteralPath $actor.stdout -Destination $StdoutPath
  Copy-Item -LiteralPath $actor.stderr -Destination $StderrPath
  $null=Get-MIRNativeProbeRemainingOutputBytes -Context $resources
  return $actor.result
}
function Get-K2213PathIdentity {
  param([Parameter(Mandatory)][string]$Path,[switch]$AllowExternalInput)
  $full = [IO.Path]::GetFullPath($Path)
  $root = $RepoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if ($full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) {
    return [pscustomobject][ordered]@{path=$full.Substring($root.Length).Replace('\','/');path_kind='repository-relative'}
  }
  Assert-K2213 ([bool]$AllowExternalInput) "artifact-outside-repository:$full"
  return [pscustomobject][ordered]@{path=$full;path_kind='external-input-file'}
}
function Get-K2213Relative { param([Parameter(Mandatory)][string]$Path)
  return (Get-K2213PathIdentity -Path $Path).path
}
function Get-K2213Artifact { param([Parameter(Mandatory)][string]$Path,[switch]$AllowExternalInput)
  $item = Get-Item -LiteralPath $Path -Force
  Assert-K2213 (-not (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) "artifact-reparse:$Path"
  $identity = Get-K2213PathIdentity -Path $item.FullName -AllowExternalInput:$AllowExternalInput
  [pscustomobject][ordered]@{path=$identity.path;path_kind=$identity.path_kind;bytes=[long]$item.Length;raw_sha256=Get-K2213Sha256 $item.FullName}
}
function Read-K2213Json { param([Parameter(Mandatory)][string]$Path,[string]$Code)
  Assert-K2213 (Test-Path -LiteralPath $Path -PathType Leaf) "$Code-missing"
  try { return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100) } catch { Fail-K2213 "$Code-invalid-json" }
}
function Get-K2213ZipInfo { param([Parameter(Mandatory)][string]$Path)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entries = @($archive.Entries | Where-Object { $_.FullName -match '^[^/]+/info[.]json$' })
    Assert-K2213 ($entries.Count -eq 1) "archive-info-json-count:$([IO.Path]::GetFileName($Path))"
    $reader = [IO.StreamReader]::new($entries[0].Open())
    try { $json = $reader.ReadToEnd() } finally { $reader.Dispose() }
    try { return ($json | ConvertFrom-Json -Depth 20) } catch { Fail-K2213 "archive-info-json-invalid:$([IO.Path]::GetFileName($Path))" }
  } finally { $archive.Dispose() }
}
function Assert-K2213ArchiveIdentity {
  param([string]$Path,[string]$ExpectedName,[string]$ExpectedVersion,[string]$ExpectedSha256)
  Assert-K2213 (Test-Path -LiteralPath $Path -PathType Leaf) "archive-missing:$ExpectedName"
  Assert-K2213 ((Get-K2213Sha256 $Path) -ceq $ExpectedSha256) "archive-sha256:$ExpectedName"
  $info = Get-K2213ZipInfo $Path
  Assert-K2213 ([string]$info.name -ceq $ExpectedName) "archive-name:$ExpectedName"
  Assert-K2213 ([string]$info.version -ceq $ExpectedVersion) "archive-version:$ExpectedName"
}
function Read-K2213BaseLibraryInputs {
  param([string]$Library,[object[]]$Inputs,[ValidatePattern('^2[.]1[.](?:0|[1-9][0-9]*)$')][string]$EngineVersion='2.1.20')
  Assert-MIRLibraryPath $Library
  $hashes=[ordered]@{}
  $rows=@(foreach($name in @('base','elevated-rails','quality','recycler','space-age')){[ordered]@{name=$name;version=$EngineVersion;enabled=$true}})
  foreach($inputRow in $Inputs){
    $archive=Join-Path $Library ([string]$inputRow.file_name)
    Assert-K2213ArchiveIdentity -Path $archive -ExpectedName $inputRow.identity.name -ExpectedVersion $inputRow.identity.version -ExpectedSha256 $inputRow.expected_sha256
    $hashes[$inputRow.file_name]=[string]$inputRow.expected_sha256
    $rows+=[ordered]@{name=$inputRow.identity.name;version=$inputRow.identity.version;enabled=$true}
  }
  return [pscustomobject]@{mod_list=[ordered]@{mods=$rows};archive_hashes=$hashes}
}
function Read-K2213DirectLibraryInputs {
  param([string]$Library,[object[]]$Inputs,[string]$FixtureRoot,[ValidatePattern('^2[.]1[.](?:0|[1-9][0-9]*)$')][string]$EngineVersion='2.1.20')
  $base=Read-K2213BaseLibraryInputs -Library $Library -Inputs $Inputs -EngineVersion $EngineVersion
  $hashes=$base.archive_hashes
  $rows=@($base.mod_list.mods)
  $info=Get-Content -LiteralPath (Join-Path $FixtureRoot 'info.json') -Raw|ConvertFrom-Json
  $name=$info.name+'_'+$info.version+'.zip'
  $fixtureArchive=Join-Path $Library $name
  Assert-K2213 (Test-Path -LiteralPath $fixtureArchive -PathType Leaf) 'install-current-fixture-once-in-library'
  Assert-MIRLibraryPath $fixtureArchive
  $sourceFiles=@(Get-ChildItem -LiteralPath $FixtureRoot -Recurse -File)
  $zip=[IO.Compression.ZipFile]::OpenRead($fixtureArchive)
  try{
    Assert-K2213 ($zip.Entries.Count -eq $sourceFiles.Count) 'library-fixture-membership'
    foreach($file in $sourceFiles){
      $relative=[IO.Path]::GetRelativePath($FixtureRoot,$file.FullName).Replace('\','/')
      $entry=$zip.GetEntry($info.name+'_'+$info.version+'/'+$relative)
      Assert-K2213 ($null -ne $entry -and $entry.Length -eq $file.Length) "library-fixture-member:$relative"
      $stream=$entry.Open()
      try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
      Assert-K2213 ($hash -ceq (Get-K2213Sha256 $file.FullName)) "library-fixture-source:$relative"
    }
  }finally{$zip.Dispose()}
  $hashes[$name]=Get-K2213Sha256 $fixtureArchive
  $rows+=[ordered]@{name=$info.name;version=$info.version;enabled=$true}
  return [pscustomobject]@{mod_list=[ordered]@{mods=$rows};archive_hashes=$hashes;fixture_archive=$fixtureArchive}
}
function Get-K2213FixtureEnvelope {
  param([Parameter(Mandatory)][string]$Path,[ValidatePattern('^4[.](?:0|[1-9][0-9]{0,4})[.](?:0|[1-9][0-9]?)$')][string]$SourceVersion='4.2.1')
  $text = Get-Content -Raw -LiteralPath $Path
  $fixtureId = 'k2-213-imersite-continuation'
  $match = [regex]::Match($text,"(?ms)^  $fixtureId`:\s*\r?\n(?<body>.*?)(?=^  [A-Za-z0-9][A-Za-z0-9_-]*:\s*\r?\n|\z)")
  Assert-K2213 $match.Success 'registered-fixture-absent'
  $body = $match.Groups['body'].Value
  $required = @(
    'path: fixtures/assert-k2-213-imersite-continuation',
    'qualification_status: unqualified',
    'base: "2.1.21"',
    'Krastorio2: "2.1.3"',
    'Krastorio2-spaced-out: "2.0.13"',
    'more-infinite-research: "4.2.21001"',
    'input_profiles:',
    '  - fixtures/run-profiles/k2-213-imersite-f210-440.json',
    '  - fixtures/run-profiles/k2-213-imersite-f210-460.json',
    '  - fixtures/run-profiles/k2-213-imersite-f210-470.json',
    '  - fixtures/run-profiles/k2-214-imersite-f210-470.json'
  )
  foreach ($line in $required) { Assert-K2213 ($body.Contains($line,[StringComparison]::Ordinal)) "registered-fixture-field:$line" }
  $selected=Get-K2213SelectedFixtureProfile -SourceVersion $SourceVersion
  if(-not [bool]$selected.retained){
    Assert-K2213 (-not [string]::IsNullOrWhiteSpace([string]$selected.input_profile) -and $body.Contains('  - '+[string]$selected.input_profile,[StringComparison]::Ordinal)) 'registered-fixture-selected-profile'
  }
  $registration=Read-K2213CurrentFixtureRegistration -Path $Path
  if($selected.current_registration){Assert-K2213 ($registration.mir_version-ceq$selected.mir_version) 'registered-fixture-current-candidate'}
  return [pscustomobject][ordered]@{id=$fixtureId;path='fixtures/assert-k2-213-imersite-continuation';raw_sha256=Get-K2213Sha256 $Path;selected_profile=$selected}
}
function New-K2213FailureResult {
  param([string]$RunRoot,[string]$Message,$Activation,$Resources,[object[]]$AdmissionWaits=@())
  if ([string]::IsNullOrWhiteSpace($RunRoot) -or -not (Test-Path -LiteralPath $RunRoot -PathType Container)) { return }
  $terminal = $null
  if ($null -ne $Activation -and -not [bool]$Activation.closed) {
    try { $terminal = Complete-MIRLibraryActivation -Activation $Activation } catch { $terminal=@{status='recovery-required';library=$Activation.library;error=$_.Exception.Message} }
  }
  $record = [ordered]@{
    schema=2;kind='MIR42K2213ImersiteContinuationRuntimeResultV2';status='failed';
    generated_at=(Get-Date).ToUniversalTime().ToString('o');failure=[string]$Message;
    scope='exact-current-f210-k2-k2so-imersite-powder-continuation-create-and-single-reload';
    qualification=$false;support_claim=$false;release_authority=$false;publication=$false;
    input_binding=$inputBinding;
    library_activation=$terminal
    resource_runs=if($Resources){$Resources.runs.ToArray()}else{@()}
    admission_waits=$AdmissionWaits
  }
  if($Resources){Write-MIRNativeProbeResult -Context $Resources -Record $record}
}

$runRoot = ''
$activation = $null
$resources = $null
$inputBinding = $null
$admissionWaits = [Collections.Generic.List[object]]::new()
try {
  $engine = (Resolve-Path -LiteralPath $FactorioBin).Path
  $candidate = (Resolve-Path -LiteralPath $CandidateZip).Path
  $materializationPath = (Resolve-Path -LiteralPath $SourceMaterializationPath).Path
  $v5Path = if($V5ObservationResultPath){(Resolve-Path -LiteralPath $V5ObservationResultPath).Path}else{''}
  $profilePath = if($InputProfilePath){(Resolve-Path -LiteralPath $InputProfilePath).Path}else{''}
  Assert-K2213SelectedInputMode -SourceVersion $SourceVersion -V5Path $v5Path -ProfilePath $profilePath
  $outputRootFull = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputRoot))
  $buildRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build')).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  Assert-K2213 ($outputRootFull.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)) 'output-root-outside-build'

  $fixtureRegistry = Get-K2213FixtureEnvelope -Path (Join-Path $RepoRoot '.mir/fixtures.yml') -SourceVersion $SourceVersion
  $fixtureTemplateRoot = Join-Path $RepoRoot $fixtureRegistry.path
  $fixtureRoot = $fixtureTemplateRoot
  $fixtureInfoPath = Join-Path $fixtureRoot 'info.json'
  $fixtureDataPath = Join-Path $fixtureRoot 'data-final-fixes.lua'
  $fixtureControlPath = Join-Path $fixtureRoot 'control.lua'
  $fixtureSettingsPath = Join-Path $fixtureRoot 'settings-updates.lua'
  foreach ($fixturePath in @($fixtureInfoPath,$fixtureDataPath,$fixtureControlPath,$fixtureSettingsPath)) { Assert-K2213 (Test-Path -LiteralPath $fixturePath -PathType Leaf) "fixture-missing:$fixturePath" }
  $fixtureTemplateFiles=@($fixtureInfoPath,$fixtureDataPath,$fixtureControlPath,$fixtureSettingsPath)
  $fixtureInfo = Read-K2213Json -Path $fixtureInfoPath -Code 'fixture-info'
  Assert-K2213 ([string]$fixtureInfo.name -ceq 'mir-fixture-assert-k2-213-imersite-continuation') 'fixture-name'
  Assert-K2213 ([string]$fixtureInfo.version -ceq '0.1.4') 'fixture-template-version'
  Assert-K2213 ([string]$fixtureInfo.factorio_version -ceq '2.1') 'fixture-factorio-version'
  $fixtureDependencies = @($fixtureInfo.dependencies | ForEach-Object {[string]$_})
  foreach ($dependency in @('base >= 2.1.20','Krastorio2 = 2.1.3','Krastorio2-spaced-out = 2.0.13','more-infinite-research >= 4.2.21001')) {
    Assert-K2213 ($fixtureDependencies -contains $dependency) "fixture-dependency:$dependency"
  }
  Assert-K2213 ($LocalModLibraryDirs.Count -eq 1) 'one-active-flat-library-required'
  $library=(Resolve-Path -LiteralPath $LocalModLibraryDirs[0]).Path
  $plannedFixtureArchive = Join-Path $library ([string]$fixtureInfo.name + '_' + [string]$fixtureInfo.version + '.zip')
  Assert-MIRFactorioPathBudget -Path $plannedFixtureArchive -Context 'K2 continuation fixture archive path'

  $currentCandidate=Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $materializationPath -SourceVersion $SourceVersion
  $materialization=$currentCandidate.receipt

  $engineHash = Get-K2213Sha256 $engine
  $engineRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $engine))
  $runtimeApi = Join-Path $engineRoot 'doc-html/runtime-api.json'
  $expectedDependencies = Get-K2213ExpectedDependencies -SourceVersion $SourceVersion
  $predecessorLock=$null
  $inputProfile=$null
  if($profilePath){
    if(-not [bool]$fixtureRegistry.selected_profile.retained){
      $expectedProfilePath=(Resolve-Path -LiteralPath (Join-Path $RepoRoot ([string]$fixtureRegistry.selected_profile.input_profile))).Path
      Assert-K2213 ($profilePath -ceq $expectedProfilePath) 'input-profile-registry-selection'
    }
    $bound=Read-K2213ProfileInputs -Path $profilePath -ExpectedDependencies $expectedDependencies -Libraries $LocalModLibraryDirs -SourceVersion $SourceVersion
    $expectedEngineVersion=[string]$bound.profile.engine_version
    Assert-K2213 ($engineHash -ceq $bound.profile.engine_sha256) 'engine-sha256'
    Assert-K2213 ((Get-K2213Sha256 $runtimeApi) -ceq $bound.profile.runtime_api_sha256) 'engine-runtime-api'
    $inputs=@($bound.inputs)
    $fixtureProfile=$bound.fixture_profile
    $inputProfile=Get-K2213Artifact $profilePath -AllowExternalInput
  }else{
    $v5 = Read-K2213Json -Path $v5Path -Code 'v5-observation'
    Assert-K2213 ([int]$v5.schema -eq 1 -and [string]$v5.kind -ceq 'MIR42ExactK2213ForwardPathObservationResultV3' -and [string]$v5.status -ceq 'passed') 'v5-schema-status'
    foreach ($forbiddenClaim in @('qualification','support_claim','release_authority','publication')) { Assert-K2213 (-not [bool](Get-K2213Property $v5 $forbiddenClaim $true)) "v5-must-remain-non-authorizing:$forbiddenClaim" }
    $v5Mods = Get-K2213Property $v5 'exact_mods'
    foreach ($pair in @(@('base','2.1.20'),@('Krastorio2','2.1.3'),@('Krastorio2-spaced-out','2.0.13'),@('more-infinite-research','4.2.21000'))) {
      Assert-K2213 ([string](Get-K2213Property $v5Mods $pair[0] '') -ceq $pair[1]) "v5-exact-mod:$($pair[0])"
    }
    Assert-K2213 ($engineHash -ceq [string]$v5.engine.sha256) 'engine-sha256'
    Assert-K2213 ([string]$v5.engine.product_version -ceq '2.1.20') 'v5-engine-version'
    Assert-K2213 ((Get-K2213Sha256 $runtimeApi) -ceq [string]$v5.engine.bundled_runtime_api_sha256) 'engine-runtime-api'
    $expectedEngineVersion='2.1.20'
    $expectedDependencies['mir-validation-settings-overrides_0.1.0.zip']=@('mir-validation-settings-overrides','0.1.0')
    $inputs = @(Read-K2213DependencyInputs -Observation $v5 -ExpectedDependencies $expectedDependencies -Libraries $LocalModLibraryDirs -ObservationPath $v5Path)
    $fixtureProfile=Get-K2213SelectedFixtureProfile -SourceVersion $SourceVersion
    $predecessorLock=[ordered]@{result=Get-K2213Artifact $v5Path -AllowExternalInput;kind=[string]$v5.kind;status=[string]$v5.status;role='exact-engine-and-dependency-archive-lock-only';old_candidate_sha256=[string]$v5.candidate.sha256}
  }
  Assert-K2213 ((Get-Item -LiteralPath $engine).VersionInfo.ProductVersion -ceq $expectedEngineVersion) 'engine-product-version'
  $inputs += [ordered]@{source_path=$candidate;file_name=([IO.Path]::GetFileName($candidate));expected_sha256=([string]$materialization.archive_sha256);role='candidate';identity=[ordered]@{name='more-infinite-research';version=$materialization.distribution_version;materialization_record_sha256=[string]$materialization.record_sha256};provenance=[ordered]@{kind='current-candidate-materialization';raw_materialization_sha256=Get-K2213Sha256 $materializationPath};immutable=$true}
  $baseInputs=Read-K2213BaseLibraryInputs -Library $library -Inputs $inputs -EngineVersion $expectedEngineVersion
  if(-not (Get-K2213SelectedFixtureProfile -SourceVersion $SourceVersion).retained -and $PreflightOnly){
    $inputBinding=[ordered]@{
      source_commit=(& git -C $RepoRoot rev-parse HEAD).Trim();harness=Get-K2213Artifact $PSCommandPath
      candidate_sha256=[string]$materialization.archive_sha256;materialization_sha256=Get-K2213Sha256 $materializationPath
      source_version=$materialization.source_version;distribution_version=$materialization.distribution_version
      engine_version=$expectedEngineVersion;engine_sha256=$engineHash;runtime_api_sha256=Get-K2213Sha256 $runtimeApi
      input_profile=$inputProfile;predecessor_observation_lock=$predecessorLock;archive_hashes=$baseInputs.archive_hashes
      fixture=[ordered]@{template_version='0.1.4';selected_version=[string]$fixtureProfile.fixture_version;temporary_specialization_required=$true}
    }
    [pscustomobject][ordered]@{
      status='passed-preflight-only';scope='exact-current-f210-k2-k2so-imersite-continuation-input-and-envelope-validation'
      candidate_sha256=[string]$materialization.archive_sha256;source_version=$materialization.source_version;distribution_version=$materialization.distribution_version
      materialization_sha256=Get-K2213Sha256 $materializationPath;predecessor_observation_lock=$predecessorLock;input_profile=$inputProfile
      engine_version=$expectedEngineVersion;engine_sha256=$engineHash;runtime_api_sha256=Get-K2213Sha256 $runtimeApi
      fixture_registry_sha256=$fixtureRegistry.raw_sha256;fixture_template_version='0.1.4';fixture_selected_version=[string]$fixtureProfile.fixture_version
      fixture_preparation_required=$true;dependency_count=$expectedDependencies.Count;library=$library;execution_started=$false
    } | ConvertTo-Json -Depth 20
    return
  }
  $directInputs=if(-not (Get-K2213SelectedFixtureProfile -SourceVersion $SourceVersion).retained){$null}else{Read-K2213DirectLibraryInputs -Library $library -Inputs $inputs -FixtureRoot $fixtureRoot -EngineVersion $expectedEngineVersion}
  $inputBinding=[ordered]@{
    source_commit=(& git -C $RepoRoot rev-parse HEAD).Trim();harness=Get-K2213Artifact $PSCommandPath
    candidate_sha256=[string]$materialization.archive_sha256;materialization_sha256=Get-K2213Sha256 $materializationPath
    source_version=$materialization.source_version;distribution_version=$materialization.distribution_version
    engine_version=$expectedEngineVersion;engine_sha256=$engineHash;runtime_api_sha256=Get-K2213Sha256 $runtimeApi
    # Current fixtures are specialized after this binding is established.
    # Retain the authenticated base selection until its fixture archive exists;
    # preparation below replaces this with the complete direct-library set.
    input_profile=$inputProfile;predecessor_observation_lock=$predecessorLock;archive_hashes=$(if($null -ne $directInputs){$directInputs.archive_hashes}else{$baseInputs.archive_hashes})
  }

  if ($PreflightOnly) {
    [pscustomobject][ordered]@{
      status='passed-preflight-only'
      scope='exact-current-f210-k2-k2so-imersite-continuation-input-and-envelope-validation'
      candidate_sha256=[string]$materialization.archive_sha256
      source_version=$materialization.source_version;distribution_version=$materialization.distribution_version
      materialization_sha256=Get-K2213Sha256 $materializationPath
      predecessor_observation_lock=$predecessorLock
      input_profile=$inputProfile
      engine_version=$expectedEngineVersion
      engine_sha256=$engineHash
      runtime_api_sha256=Get-K2213Sha256 $runtimeApi
      fixture_registry_sha256=$fixtureRegistry.raw_sha256
      dependency_count=$expectedDependencies.Count
      library=$library
      fixture_archive_sha256=$directInputs.archive_hashes[[IO.Path]::GetFileName($directInputs.fixture_archive)]
      execution_started=$false
    } | ConvertTo-Json -Depth 20
    return
  }

  & (Join-Path $RepoRoot 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -RepoRoot $RepoRoot -MaxScanSeconds 3 -MaxEntriesPerRoot 400 -MaxWorktrees 8 -MaxBranches 32 | Out-Host
  if ($AdmissionWaitSeconds -gt 0 -and $ExpectedPeakMemoryMiB -gt 0) {
    [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
    $admissionWaits.Add((Wait-MIRDirectLibraryStartupAdmission -Policy ([pscustomobject]@{minimum_free_ram_gib=4}) -WorkRoot $outputRootFull -EstimatedPeakBytes ([int64]$MaxNewOutputMiB*1MB) -ExpectedPeakMemoryBytes ([int64]$ExpectedPeakMemoryMiB*1MB) -AdmissionWaitSeconds $AdmissionWaitSeconds -Phase 'resource-context'))
  }
  $resources=New-MIRNativeProbeResourceContext -RepoRoot $RepoRoot -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
  $runRoot=$resources.root
  [IO.Directory]::CreateDirectory($runRoot) | Out-Null
  [IO.Directory]::CreateDirectory((Join-Path $runRoot 'saves')) | Out-Null
  $fixturePreparation=$null
  if(-not (Get-K2213SelectedFixtureProfile -SourceVersion $SourceVersion).retained){
    $fixtureRoot=New-K2213SelectedFixture -Source $fixtureTemplateRoot -Run $runRoot -SourceVersion $SourceVersion -SelectedMIRVersion ([string]$materialization.distribution_version)
    $fixtureInfoPath=Join-Path $fixtureRoot 'info.json'
    $fixtureDataPath=Join-Path $fixtureRoot 'data-final-fixes.lua'
    $fixtureControlPath=Join-Path $fixtureRoot 'control.lua'
    $fixtureSettingsPath=Join-Path $fixtureRoot 'settings-updates.lua'
    foreach($fixturePath in @($fixtureInfoPath,$fixtureDataPath,$fixtureControlPath,$fixtureSettingsPath)){Assert-K2213 (Test-Path -LiteralPath $fixturePath -PathType Leaf) "selected-fixture-missing:$fixturePath"}
    $fixtureInfo=Read-K2213Json -Path $fixtureInfoPath -Code 'selected-fixture-info'
    Assert-K2213 ([string]$fixtureInfo.version-ceq[string]$fixtureProfile.fixture_version) 'selected-fixture-version'
    $fixtureDependencies=@($fixtureInfo.dependencies|ForEach-Object {[string]$_})
    foreach($dependency in @('base >= 2.1.20',('Krastorio2 = '+[string]$fixtureProfile.external_versions['Krastorio2']),('Krastorio2-spaced-out = '+[string]$fixtureProfile.external_versions['Krastorio2-spaced-out']),('more-infinite-research = '+[string]$materialization.distribution_version))){Assert-K2213 ($fixtureDependencies-contains$dependency) "selected-fixture-dependency:$dependency"}
    $prepProfile=Join-Path $runRoot 'fixture-preparation-selection.json'
    [IO.File]::WriteAllText($prepProfile,($baseInputs.mod_list|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $prepareActivation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory (Join-Path $engineRoot 'data') -ProfilePath $prepProfile -ArchiveHashes $baseInputs.archive_hashes -SettingsMode Defaults
    try{
      Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $prepareActivation
      $fixtureArchive=Join-Path $library ([string]$fixtureInfo.name+'_'+[string]$fixtureInfo.version+'.zip')
      if(-not(Test-Path -LiteralPath $fixtureArchive -PathType Leaf)){
        $fixtureArchive=Publish-MIRModDirectoryArchive -Source $fixtureRoot -Name $fixtureInfo.name -Version $fixtureInfo.version -ModsDir $library
        $resources.max_new_output_bytes-=(Get-Item -LiteralPath $fixtureArchive).Length
      }
      Assert-MIRLibraryFixtureArchive -Archive $fixtureArchive -SourceDirectory $fixtureRoot
    }finally{$fixturePreparation=Complete-MIRLibraryActivation -Activation $prepareActivation}
    $directInputs=Read-K2213DirectLibraryInputs -Library $library -Inputs $inputs -FixtureRoot $fixtureRoot -EngineVersion $expectedEngineVersion
    $inputBinding.archive_hashes=$directInputs.archive_hashes
    $inputBinding.fixture=[ordered]@{template_version='0.1.4';selected_version=[string]$fixtureInfo.version;temporary_specialization=$true;preparation_controls=$fixturePreparation}
  }
  $versionRun=Invoke-K2213NativeActor -Phase 'engine-version' -FactorioBin $engine -Arguments @('--version') -TimeoutSeconds 30
  $engineVersion=(Get-Content -LiteralPath $versionRun.stdout -Raw).Trim()
  Assert-K2213 ($engineVersion -match ('(?m)^Version:\s*'+[regex]::Escape($expectedEngineVersion)+'(?:\s|$)')) 'engine-version'
  $fixtureArchive=$directInputs.fixture_archive
  $enabled = @('base','elevated-rails','quality','recycler','space-age','more-infinite-research',[string]$fixtureInfo.name)+@(foreach($key in $expectedDependencies.Keys){$expectedDependencies[$key][0]})
  $profilePath=Join-Path $runRoot 'selection.json'
  [IO.File]::WriteAllText($profilePath,($directInputs.mod_list|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory (Join-Path $engineRoot 'data') -ProfilePath $profilePath -ArchiveHashes $directInputs.archive_hashes -SettingsMode Defaults
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $activation
  $modListPath = Join-Path $runRoot 'active-mod-list.json'
  [IO.File]::WriteAllBytes($modListPath,$activation.mod_list_bytes)
  $modList = Read-K2213Json -Path $modListPath -Code 'mod-list'
  $enabledRows = @($modList.mods | Where-Object {[bool]$_.enabled} | ForEach-Object {[string]$_.name} | Sort-Object)
  Assert-K2213 ((@($enabledRows) -join '|') -ceq (@($enabled | Sort-Object) -join '|')) 'mod-list-exact-enabled-closure'
  foreach ($dlc in @('elevated-rails','quality','recycler','space-age')) {
    $row = @($modList.mods | Where-Object {[string]$_.name -ceq $dlc})
    Assert-K2213 ($row.Count -eq 1 -and [bool]$row[0].enabled) "mod-list-observed-dlc:$dlc"
  }
  # The continuation fixture proves the current declaration's default zero
  # configuration, with the fixture's explicit diagnostic-report default.
  # It never inherits an unbound settings file from a previous test.
  Assert-K2213 (-not (Test-Path -LiteralPath (Join-Path $library 'mod-settings.dat') -PathType Leaf)) 'unexpected-unbound-mod-settings'

  $load = Invoke-MIRFactorioLoadCheck -FactorioBin $engine -UserDataDir $runRoot -ScenarioName 'k2-213-imersite-continuation' -ScenarioTimeoutSeconds $CreateTimeoutSeconds -LibraryActivation $activation -ActiveModsObserver $fixtureInfo.name
  Assert-K2213 ([bool]$load.passed -and -not [bool]$load.timed_out -and [int]$load.exit_code -eq 0) 'create'
  Assert-K2213 ([string]$load.stderr_sha256 -ceq 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855') 'create-stderr'
  $loadLog = [IO.File]::ReadAllText([string]$load.factorio_log)
  Assert-K2213 ($loadLog.Contains('[MIR42_K2_213_IMERSITE_CONTINUATION_DATA]',[StringComparison]::Ordinal)) 'create-data-marker'
  Assert-K2213 ($loadLog.Contains('[MIR42_K2_213_IMERSITE_CONTINUATION] stage=initial;completed_level=4;next_level=5;bonus=0.08;progress=0.42',[StringComparison]::Ordinal)) 'create-initial-marker'
  $reload = Invoke-MIRFactorioReloadContract -FactorioBin $engine -UserDataDir $runRoot -ScenarioName 'k2-213-imersite-continuation' -SavePath $load.save -RequiredReloadCount 1 -MaxReloadDurationSeconds $ReloadTimeoutSeconds -RequiredLogFragments @('[MIR42_K2_213_IMERSITE_CONTINUATION] stage=reload;completed_level=4;next_level=5;bonus=0.08;progress=0.42','[MIR42_K2_213_IMERSITE_PRODUCTION] ore=300;powder=324;sand=324;control_powder=300;control_sand=300;after_reload=true') -LibraryActivation $activation -ActiveModsObserver $fixtureInfo.name
  Assert-K2213 ([bool]$reload.passed) 'single-reload'
  $productionPath=Join-Path $runRoot 'script-output/k2-imersite-production.json'
  $production=Read-K2213Json -Path $productionPath -Code 'production-output'
  Assert-K2213 ($production.status -ceq 'passed' -and @($production.cases).Count -eq 2) 'production-result'
  foreach($row in @(@{force='player';output=324;bonus=0.08},@{force='mir-k2-unresearched';output=300;bonus=0})){
    $actual=@($production.cases|Where-Object force -ceq $row.force)
    Assert-K2213 ($actual.Count -eq 1 -and $actual[0].ore -eq 300 -and $actual[0].powder -eq $row.output -and $actual[0].sand -eq $row.output -and $actual[0].bonus -eq $row.bonus) 'production-counts'
  }
  # Capture locators while the archive read handles are still held; a later
  # activation may select different MIR bytes under the same numeric version.
  $dependencyArtifacts = @($inputs | Where-Object {[string]$_.role -ceq 'dependency-mod'} | ForEach-Object { Get-K2213Artifact (Join-Path $library $_.file_name) -AllowExternalInput })
  $candidateArtifact = Get-K2213Artifact (Join-Path $library ([IO.Path]::GetFileName($candidate))) -AllowExternalInput
  $fixtureArtifact = Get-K2213Artifact $fixtureArchive -AllowExternalInput
  $terminal = Complete-MIRLibraryActivation -Activation $activation
  $activation = $null
  $result = [ordered]@{
    schema=2;kind='MIR42K2213ImersiteContinuationRuntimeResultV2';status='passed';generated_at=(Get-Date).ToUniversalTime().ToString('o');
    scope='exact-current-f210-k2-k2so-imersite-powder-continuation-create-and-single-reload';
    qualification=$false;support_claim=$false;release_authority=$false;publication=$false;
    candidate=[ordered]@{archive=$candidateArtifact;materialization=Get-K2213Artifact $materializationPath;materialization_record_sha256=[string]$materialization.record_sha256;package_source_sha256=[string]$materialization.package_source_sha256};
    source=[ordered]@{commit=(& git -C $RepoRoot rev-parse HEAD).Trim();tree=(& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim();source_version=$materialization.source_version;distribution_version=$materialization.distribution_version;harness=Get-K2213Artifact $PSCommandPath};
    predecessor_observation_lock=$predecessorLock;input_profile=$inputProfile;fixture_preparation=$fixturePreparation;
    engine=[ordered]@{path=Get-K2213PathIdentity $engine -AllowExternalInput;product_version=$expectedEngineVersion;executable_sha256=$engineHash;bundled_runtime_api_sha256=Get-K2213Sha256 $runtimeApi};
    fixture=[ordered]@{registration=$fixtureRegistry;template_files=@($fixtureTemplateFiles|ForEach-Object{Get-K2213Artifact $_});files=@(Get-K2213Artifact $fixtureInfoPath;Get-K2213Artifact $fixtureDataPath;Get-K2213Artifact $fixtureControlPath;Get-K2213Artifact $fixtureSettingsPath);archive=$fixtureArtifact};
    library_activation=$terminal;dependency_archives=@($dependencyArtifacts | Sort-Object path);mod_list=Get-K2213Artifact $modListPath;startup_settings='candidate-defaults-no-unbound-mod-settings';
    create=[ordered]@{duration_seconds=$load.duration_seconds;save=Get-K2213Artifact $load.save;stdout=Get-K2213Artifact $load.stdout;stderr=Get-K2213Artifact $load.stderr;factorio_log=Get-K2213Artifact $load.factorio_log};
    reload=$reload;
    production=[ordered]@{evidence=Get-K2213Artifact $productionPath;benchmark_ticks=25000;recipe='kr-imersite-powder';machine='kr-crusher';cases=$production.cases};
    resource_runs=$resources.runs.ToArray();
    admission_waits=$admissionWaits.ToArray();
    non_claims=@('The supplied V5 observation remains non-authorizing and is not rebound.','Only generated MIR Imersite powder continuation is exercised. Native Imersite crystal ownership and witnessed withheld K2 routes remain outside this receipt.','No player delivery, broad K2 admission, support, release, signing, or publication claim.')
  }
  $resultPath = Join-Path $runRoot 'result.json'
  Write-MIRNativeProbeResult -Context $resources -Record $result
  Write-Host "[MIR42_K2_213_IMERSITE_CONTINUATION_RUNTIME] $(Get-K2213Relative $resultPath)"
} catch {
  $failure = $_.Exception.Message
  $waitFailure=$_.Exception.Data['mir_direct_startup_admission_wait']
  if($null-ne$waitFailure){$admissionWaits.Add($waitFailure)}
  $_.Exception.Data['mir_k2213_admission_waits']=$admissionWaits.ToArray()
  try{New-K2213FailureResult -RunRoot $runRoot -Message $failure -Activation $activation -Resources $resources -AdmissionWaits $admissionWaits.ToArray()}catch{Write-Warning 'Failed K2 result exceeded its output budget; owned ledgers remain preserved.'}
  throw
}
