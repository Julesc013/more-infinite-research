# Disposable native scenarios share only the process/library custody host.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ArchiveLibrary,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$ProfilePath,
  [Parameter(Mandatory)][string[]]$FixtureSources,
  [string]$ExpectedMIRArchiveSha256='',
  [string]$ActiveModsObserver='',
  [Parameter(Mandatory)][string]$CaseName,
  [Parameter(Mandatory)][string]$OutputRoot,
  [string[]]$ConsumerMarkers=@(),
  [ValidateSet('load','configuration')][string]$ProductionConsumerStage='load',
  # Empty retains the F200/F210 runner byte path.  A selected reduced target
  # uses the compatible historical server/reload path below.
  [string]$HistoricalTarget='',
  [string]$HistoricalFixtureMetadataPath='',
  # A distinct predecessor -> MIR5 fixture protocol. It deliberately shares
  # the historical engine runner but not the fresh historical-native identity.
  [ValidateSet('','published','mir5')][string]$HistoricalTransitionStage='',
  [string]$HistoricalTransitionFixtureMetadataPath='',
  # The one fresh published F110 source leg for the F110 -> F200 engine hop.
  # It uses the F110 process path without becoming a historical fixture protocol.
  [switch]$F110PublishedCrossSource,
  # Direct protected4.7.3 F110 save to the current same-edition successor.
  [switch]$F110SameEditionSuccessor,
  # The MIR5 F100 -> F110 laser identity/effect-category boundary.
  [ValidateSet('','source','successor')][string]$F100F110LaserStage='',
  # Exact published4.7.3 F100 witness extension and its two forward endpoints.
  [ValidateSet('','source','bridge','f110','f210')][string]$PublishedF100ForwardStage='',
  [switch]$CreateOnly,
  # Active runtime seeds are earned by the selected fixture before the
  # benchmark loads the save.  This is deliberately narrower than CreateOnly:
  # agriculture must complete its two real labs before the pending planting
  # save exists, while repair must stop before its first post-load damage.
  [switch]$ActiveSeedOnly,
  [ValidateSet('','repair-stress','agriculture-scale')][string]$ActiveSeedKind='',
  [switch]$MIRAbsent,
  [string]$InputSavePath='',
  [string]$ExpectedInputSaveSha256='',
  [ValidateRange(30,600)][int]$TimeoutSeconds=180,
  [ValidateRange(128,8192)][int]$ExpectedPeakMemoryMiB=512,
  [ValidateRange(0,60)][int]$AdmissionWaitSeconds=30,
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Assert-Fixture([bool]$Condition,[string]$Message) {
  if(-not $Condition){throw "[mir5-native-fixture] $Message"}
}
function Get-FixtureSha([string]$Path) {
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
function Get-FixtureCreateArguments([string]$Seed,[string]$Case,[bool]$OnlyCreate) {
  $arguments=@('--create',$Seed)
  # The paired Library experiment needs an explicit common terrain input.
  # Other fresh fixtures retain their existing creation arguments.
  if($OnlyCreate -and $Case -ceq 'library-paired-browser') {
    $arguments+=@('--map-gen-seed','424242')
  }
  return $arguments
}
function Assert-DeclaredFixtureInputs([Collections.IDictionary]$ProfileDefinition,$EngineIdentity,[Collections.IDictionary]$ArchiveHashes) {
  Assert-MIRDirectLibraryStartupDeclaredInputs -ProfileDefinition $ProfileDefinition -EngineIdentity $EngineIdentity -ArchiveHashes $ArchiveHashes -ErrorPrefix 'mir5-native-fixture'
}
function Assert-FixtureLog([string]$Text) {
  Assert-Fixture (-not [regex]::IsMatch($Text,'(?im)^\s*\d+[.]\d+\s+Error\b|^Error while running event\b|\bException at tick\b|\bnon-recoverable error\b|^stack traceback:$')) 'fatal native diagnostic'
}
function Test-F110PublishedCrossSourceRelativePath([string]$Path) {
  return (
    $Path -cne '..' -and
    -not $Path.StartsWith('..'+[IO.Path]::DirectorySeparatorChar) -and
    $Path -cnotmatch '^[A-Za-z]:' -and
    -not $Path.StartsWith('\') -and
    -not $Path.StartsWith('/') -and
    -not [IO.Path]::IsPathRooted($Path) -and
    -not [IO.Path]::IsPathFullyQualified($Path)
  )
}
function Get-F110PublishedCrossSourceFixture([string]$Repo,[hashtable]$ProfileDefinition,[object[]]$ProfileRows,[string[]]$Sources,[string]$EngineData,[string]$Engine,[string]$ExpectedMIRSha256,[string]$Case,[bool]$Historical,[bool]$HistoricalTransition,[bool]$Create,[bool]$Absent,[bool]$Active,[string]$ActiveKind,[string]$InputSave,[string]$InputSaveSha256,[string]$Observer,[object[]]$Markers,[string]$HistoricalTarget,[string]$HistoricalMetadata,[string]$TransitionStage,[string]$TransitionMetadata,[string]$ExpectedEngineSha256='B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1',[bool]$SameEditionSuccessor=$false) {
  Assert-Fixture (-not $Historical -and -not $HistoricalTransition -and -not $Create -and -not $Absent -and -not $Active) 'F110 published cross source permits only a fresh installed-MIR source run'
  if($SameEditionSuccessor){
    Assert-Fixture ([string]::IsNullOrWhiteSpace($ActiveKind) -and -not [string]::IsNullOrWhiteSpace($InputSave) -and $InputSaveSha256.ToUpperInvariant() -ceq 'D524AA78440F242B179A1E9BC40BF89B87C1A66E99F64C14D3250DEAEBB69253') 'F110 same-edition successor requires the protected D524 source save'
  }else{
    Assert-Fixture ([string]::IsNullOrWhiteSpace($ActiveKind) -and [string]::IsNullOrWhiteSpace($InputSave) -and [string]::IsNullOrWhiteSpace($InputSaveSha256)) 'F110 published cross source does not accept active or input-save modes'
  }
  $mirVersion=if($SameEditionSuccessor){'5.0.11000'}else{'4.7.11003'}
  $fixtureVersion=if($SameEditionSuccessor){'0.3.0'}else{'0.1.0'}
  $profileKind=if($SameEditionSuccessor){'mir5-f110-same-edition-successor'}else{'mir5-f110-f200-transition-source'}
  $mirSha=if($SameEditionSuccessor){'1C3D982CD048D3C83BF75108F1F9AC769CE0DC833A2DE056CDE16EF8AE2925A9'}else{'66C127D8BFC1919FA88F19D2D9B3047316A1B90401CAA05A6D05979B7A099D1E'}
  Assert-Fixture ([string]::IsNullOrWhiteSpace($Observer) -and $Markers.Count -eq 0) 'F110 published cross source does not accept modern observers or consumers'
  Assert-Fixture ([string]::IsNullOrWhiteSpace($HistoricalTarget) -and [string]::IsNullOrWhiteSpace($HistoricalMetadata) -and [string]::IsNullOrWhiteSpace($TransitionStage) -and [string]::IsNullOrWhiteSpace($TransitionMetadata)) 'F110 published cross source does not accept historical fixture parameters'
  Assert-Fixture ($Case -ceq 'f110-f200-transition') 'F110 published cross source case differs'
  Assert-Fixture ($ExpectedMIRSha256.ToUpperInvariant() -ceq $mirSha) 'F110 published cross source MIR archive hash differs'
  $expectedRows=@('base|1.1.110|True',('more-infinite-research|'+$mirVersion+'|True'),('mir-fixture-mir5-f110-f200-transition|'+$fixtureVersion+'|True'))
  $actualRows=@($ProfileRows|ForEach-Object {[string]$_.name+'|'+[string]$_.version+'|'+[string]$_.enabled})
  Assert-Fixture ($actualRows.Count -eq $expectedRows.Count -and (($actualRows -join "`n") -ceq ($expectedRows -join "`n"))) 'F110 published cross source profile differs'
  Assert-Fixture ($ProfileDefinition.schema -eq 1 -and [string]$ProfileDefinition.kind -ceq $profileKind -and [string]$ProfileDefinition.target -ceq 'f110' -and [string]$ProfileDefinition.factorio_line -ceq '1.1' -and [string]$ProfileDefinition.settings_mode -ceq 'Defaults') 'F110 published cross source profile metadata differs'
  Assert-Fixture ($ProfileDefinition.engine -is [Collections.IDictionary] -and [string]$ProfileDefinition.engine.version -ceq '1.1.110' -and [string]$ProfileDefinition.engine.sha256 -ceq $ExpectedEngineSha256) 'F110 published cross source profile engine differs'
  Assert-Fixture ($ProfileDefinition.archive_sha256 -is [Collections.IDictionary] -and $ProfileDefinition.archive_sha256.Count -eq 1 -and [string]$ProfileDefinition.archive_sha256['more-infinite-research_'+$mirVersion+'.zip'] -ceq $ExpectedMIRSha256.ToUpperInvariant()) 'F110 published cross source profile archive differs'
  $base=Get-Content -LiteralPath (Join-Path $EngineData 'base/info.json') -Raw|ConvertFrom-Json -AsHashtable
  Assert-Fixture ([string]$base.version -ceq '1.1.110') 'F110 published cross source base differs'
  Assert-Fixture ((Get-FixtureSha $Engine) -ceq $ExpectedEngineSha256) 'F110 published cross source executable differs'
  Assert-Fixture ($Sources.Count -eq 1) 'F110 published cross source requires one fixture source'
  $repoRoot=(Resolve-Path -LiteralPath $Repo).Path
  $source=(Resolve-Path -LiteralPath $Sources[0]).Path
  $sourceRelative=[IO.Path]::GetRelativePath($repoRoot,$source)
  Assert-Fixture (Test-F110PublishedCrossSourceRelativePath $sourceRelative) 'F110 published cross source fixture must remain inside executing checkout'
  $canonical=Join-Path $repoRoot $(if($SameEditionSuccessor){'tests/fixtures/f110-f200-transition/f110/successor'}else{'tests/fixtures/f110-f200-transition/f110/published-4.7.3'})
  $shared=Join-Path $repoRoot 'tests/fixtures/f110-f200-transition/shared'
  $authoritative=[ordered]@{
    'catalogue.lua'=Join-Path $canonical 'catalogue.lua'
    'control.lua'=Join-Path $canonical 'control.lua'
    'data-final-fixes.lua'=Join-Path $canonical 'data-final-fixes.lua'
    'info.json'=Join-Path $canonical 'info.json'
    'settings-updates.lua'=Join-Path $canonical 'settings-updates.lua'
    'fixture_control.lua'=Join-Path $shared 'control.lua'
    'fixture_data_final.lua'=Join-Path $shared 'data-final-fixes.lua'
  }
  $files=@(Get-ChildItem -LiteralPath $source -Recurse -File -Force)
  $directories=@(Get-ChildItem -LiteralPath $source -Recurse -Directory -Force)
  $actual=@($files|ForEach-Object {[IO.Path]::GetRelativePath($source,$_.FullName).Replace('\','/')}|Sort-Object)
  $expected=@($authoritative.Keys|Sort-Object)
  Assert-Fixture ($directories.Count -eq 0 -and $actual.Count -eq $expected.Count -and (($actual -join "`n") -ceq ($expected -join "`n"))) 'F110 published cross source stage members differ'
  foreach($relative in $expected){
    $actualPath=Join-Path $source $relative
    $resolvedActual=(Resolve-Path -LiteralPath $actualPath).Path
    $actualRelative=[IO.Path]::GetRelativePath($source,$resolvedActual)
    Assert-Fixture (Test-F110PublishedCrossSourceRelativePath $actualRelative) "F110 published cross source stage member leaves composition: $relative"
    $expectedPath=$authoritative[$relative]
    Assert-Fixture (Test-Path -LiteralPath $expectedPath -PathType Leaf) "F110 published cross source authoritative member missing: $relative"
    $resolvedExpected=(Resolve-Path -LiteralPath $expectedPath).Path
    $expectedRelative=[IO.Path]::GetRelativePath($repoRoot,$resolvedExpected)
    Assert-Fixture (Test-F110PublishedCrossSourceRelativePath $expectedRelative) "F110 published cross source authoritative member leaves checkout: $relative"
    Assert-Fixture ((Get-FixtureSha $resolvedActual) -ceq (Get-FixtureSha $resolvedExpected)) "F110 published cross source stage member differs: $relative"
  }
  $info=Get-Content -LiteralPath (Join-Path $source 'info.json') -Raw|ConvertFrom-Json -AsHashtable
  Assert-Fixture ([string]$info.name -ceq 'mir-fixture-mir5-f110-f200-transition' -and [string]$info.version -ceq $fixtureVersion -and [string]$info.factorio_version -ceq '1.1') 'F110 published cross source fixture identity differs'
  Assert-Fixture ((@($info.dependencies) -join "`n") -ceq (('base >= 1.1.110',('more-infinite-research = '+$mirVersion)) -join "`n")) 'F110 published cross source fixture dependencies differ'
  [pscustomobject][ordered]@{source=$source;name=[string]$info.name;version=[string]$info.version}
}
function Get-F100F110LaserFixture([string]$Repo,[hashtable]$Profile,[string[]]$Sources,[string]$EngineData,[string]$Engine,[string]$MIRSha,[string]$Case,[string]$Stage,[bool]$OtherModes,[string]$InputSave,[string]$InputSha,[string]$ExpectedEngineSha='') {
  Assert-Fixture ($Stage -cin @('source','successor') -and -not $OtherModes) 'laser transition requires one exclusive full fixture stage'
  Assert-Fixture ($Case -ceq 'f100-f110-laser-transition') 'laser transition case differs'
  $sourceStage=$Stage -ceq 'source'
  $target=if($sourceStage){'f100'}else{'f110'}
  $line=if($sourceStage){'1.0'}else{'1.1'}
  $baseVersion=if($sourceStage){'1.0.0'}else{'1.1.110'}
  $mirVersion=if($sourceStage){'5.0.10000'}else{'5.0.11000'}
  $fixtureVersion=if($sourceStage){'0.1.0'}else{'0.2.0'}
  if(-not $ExpectedEngineSha){$ExpectedEngineSha=if($sourceStage){'99F1CE207A04296EF7D797E4A98AA98DDE4F02EE653C9DF736AC33A676FD4F70'}else{'B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1'}}
  if($sourceStage){
    Assert-Fixture (-not $InputSave -and -not $InputSha) 'laser source must create its own fresh save'
  }else{
    Assert-Fixture ($InputSave -and $InputSha -cmatch '^[A-Fa-f0-9]{64}$' -and $Profile.ContainsKey('protected_source_sha256') -and $InputSha.ToUpperInvariant() -ceq [string]$Profile.protected_source_sha256) 'laser successor requires the pinned protected source save'
  }
  Assert-Fixture ($Profile.schema -eq 1 -and [string]$Profile.kind -ceq 'mir-f100-f110-laser-transition' -and [string]$Profile.stage -ceq $Stage -and [string]$Profile.target -ceq $target -and [string]$Profile.factorio_line -ceq $line -and [string]$Profile.settings_mode -ceq 'Defaults') 'laser profile metadata differs'
  $expectedRows=@(('base|'+$baseVersion+'|True'),('more-infinite-research|'+$mirVersion+'|True'),('mir-fixture-f100-f110-laser|'+$fixtureVersion+'|True'))
  $actualRows=@($Profile.mods|ForEach-Object {[string]$_.name+'|'+[string]$_.version+'|'+[string]$_.enabled})
  Assert-Fixture ($actualRows.Count -eq 3 -and ($actualRows -join "`n") -ceq ($expectedRows -join "`n")) 'laser selected closure differs'
  Assert-Fixture ($MIRSha -cmatch '^[A-Fa-f0-9]{64}$' -and $Profile.archive_sha256 -is [Collections.IDictionary] -and $Profile.archive_sha256.Count -eq 1 -and [string]$Profile.archive_sha256['more-infinite-research_'+$mirVersion+'.zip'] -ceq $MIRSha.ToUpperInvariant()) 'laser MIR archive pin differs'
  $base=Get-Content -LiteralPath (Join-Path $EngineData 'base/info.json') -Raw|ConvertFrom-Json -AsHashtable
  Assert-Fixture ([string]$base.version -ceq $baseVersion -and [string]$Profile.engine.version -ceq $baseVersion -and [string]$Profile.engine.sha256 -ceq $ExpectedEngineSha -and (Get-FixtureSha $Engine) -ceq $ExpectedEngineSha) 'laser engine pin differs'
  Assert-Fixture ($Sources.Count -eq 1) 'laser transition requires one composed fixture'
  $repoRoot=(Resolve-Path -LiteralPath $Repo).Path
  $source=(Resolve-Path -LiteralPath $Sources[0]).Path
  Assert-Fixture (Test-F110PublishedCrossSourceRelativePath ([IO.Path]::GetRelativePath($repoRoot,$source))) 'laser fixture leaves executing checkout'
  $canonical=Join-Path $repoRoot ('tests/fixtures/f100-f110-laser/'+$Stage)
  $shared=Join-Path $repoRoot 'tests/fixtures/f100-f110-laser/shared'
  $members=[ordered]@{}
  foreach($name in @('info.json','stage.lua','control.lua','data-final-fixes.lua','settings-updates.lua')){$members[$name]=Join-Path $canonical $name}
  $members['fixture_control.lua']=Join-Path $shared 'control.lua'
  $members['fixture_data_final.lua']=Join-Path $shared 'data-final-fixes.lua'
  $members['fixture_settings.lua']=Join-Path $shared 'settings-updates.lua'
  $files=@(Get-ChildItem -LiteralPath $source -File -Force)
  Assert-Fixture ($files.Count -eq $members.Count -and @(Get-ChildItem -LiteralPath $source -Directory -Force).Count -eq 0) 'laser fixture membership differs'
  foreach($name in $members.Keys){
    $actual=Join-Path $source $name
    Assert-Fixture (Test-Path -LiteralPath $actual -PathType Leaf) 'laser composed member absent'
    $resolved=(Resolve-Path -LiteralPath $actual).Path
    Assert-Fixture (Test-F110PublishedCrossSourceRelativePath ([IO.Path]::GetRelativePath($source,$resolved))) 'laser composed member leaves fixture'
    $expected=(Resolve-Path -LiteralPath $members[$name]).Path
    Assert-Fixture (Test-F110PublishedCrossSourceRelativePath ([IO.Path]::GetRelativePath($repoRoot,$expected))) 'laser canonical member leaves checkout'
    Assert-Fixture ((Get-FixtureSha $actual) -ceq (Get-FixtureSha $members[$name])) ('laser canonical member differs: '+$name)
  }
  $info=Get-Content -LiteralPath (Join-Path $source 'info.json') -Raw|ConvertFrom-Json -AsHashtable
  Assert-Fixture ([string]$info.name -ceq 'mir-fixture-f100-f110-laser' -and [string]$info.version -ceq $fixtureVersion -and [string]$info.factorio_version -ceq $line) 'laser fixture info differs'
  return [pscustomobject]@{source=$source;name=[string]$info.name;version=$fixtureVersion;stage=$Stage;factorio_version=$line}
}
function Read-PublishedF100DirectRefusal([string]$Repo,[Collections.IDictionary]$Binding,[string]$InputSha) {
  Assert-Fixture ($null -ne $Binding) 'published F100 bridge requires retained refusal bodies'
  function Read-RefusalBody($Reference,[int]$MaximumBytes) {
    Assert-Fixture ($Reference -is [Collections.IDictionary] -and $Reference.path -is [string] -and $Reference.sha256 -cmatch '^[A-F0-9]{64}$') 'refusal body reference differs'
    $path=if([IO.Path]::IsPathRooted($Reference.path)){$Reference.path}else{Join-Path $Repo $Reference.path}
    $file=Get-Item -LiteralPath $path -ErrorAction Stop
    Assert-Fixture (-not $file.PSIsContainer -and $file.Length -gt 0 -and $file.Length -le $MaximumBytes -and (Get-FixtureSha $file.FullName) -ceq $Reference.sha256) 'retained refusal body length/hash differs'
    [pscustomobject]@{path=$file.FullName;text=[IO.File]::ReadAllText($file.FullName)}
  }
  function Read-RefusalJson([string]$Text) {
    $document=[Text.Json.JsonDocument]::Parse($Text,[Text.Json.JsonDocumentOptions]@{MaxDepth=32})
    function Test-UniqueRefusalKeys($Element) {
      if($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object){
        $keys=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($property in $Element.EnumerateObject()){
          Assert-Fixture ($keys.Add($property.Name)) 'duplicate refusal JSON property'
          Test-UniqueRefusalKeys $property.Value
        }
      }elseif($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array){foreach($item in $Element.EnumerateArray()){Test-UniqueRefusalKeys $item}}
    }
    try{Test-UniqueRefusalKeys $document.RootElement}finally{$document.Dispose()}
    $Text|ConvertFrom-Json -AsHashtable -Depth 32
  }
  $resultBody=Read-RefusalBody $Binding.result 2MB
  $profileBody=Read-RefusalBody $Binding.profile 128KB
  $stdoutBody=Read-RefusalBody $Binding.stdout 2MB
  $ledgerBody=Read-RefusalBody $Binding.ledger 2MB
  $result=Read-RefusalJson $resultBody.text
  $direct=Read-RefusalJson $profileBody.text
  $endpoint=$Binding.endpoint
  Assert-Fixture ($endpoint -is [Collections.IDictionary] -and $endpoint.target -cin @('f110','f210') -and $endpoint.mir_sha256 -cmatch '^[A-F0-9]{64}$' -and $endpoint.fixture_sha256 -cmatch '^[A-F0-9]{64}$' -and $endpoint.source_revision -cmatch '^[a-f0-9]{40}$' -and $endpoint.harness_sha256 -cmatch '^[A-F0-9]{64}$') 'direct refusal endpoint pins differ'
  $tuple=if($endpoint.target -ceq 'f110'){@('1.1','1.1.110','5.0.11000','0.4.0','B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1')}else{@('2.1','2.1.23','5.0.21000','0.5.0','8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38')}
  $line,$base,$mir,$fixture,$engineSha=$tuple
  Assert-Fixture ($direct.schema -eq 1 -and $direct.kind -ceq 'published-f100-forward' -and $direct.stage -ceq $endpoint.target -and $direct.target -ceq $endpoint.target -and $direct.factorio_line -ceq $line -and $direct.settings_mode -ceq 'Defaults' -and $direct.predecessor_origin -ceq 'published-f100-4.7.10003' -and $direct.protected_source_sha256 -ceq $InputSha) 'direct refusal profile/source differs'
  Assert-Fixture ($direct.engine.version -ceq $base -and $direct.engine.sha256 -ceq $engineSha -and $result.engine.base_version -ceq $base -and $result.engine.sha256 -ceq $engineSha) 'direct refusal destination engine differs'
  $selected=@($direct.mods|ForEach-Object {[string]$_.name+'|'+[string]$_.version+'|'+[string]$_.enabled})
  $wanted=@(('base|'+$base+'|True'),('more-infinite-research|'+$mir+'|True'),('mir-fixture-mir5-historical-transition|'+$fixture+'|True'))
  Assert-Fixture ($selected.Count -eq 3 -and ($selected-join "`n") -ceq ($wanted-join "`n") -and $direct.archive_sha256.Count -eq 2 -and $direct.archive_sha256['more-infinite-research_'+$mir+'.zip'] -ceq $endpoint.mir_sha256 -and $direct.archive_sha256['mir-fixture-mir5-historical-transition_'+$fixture+'.zip'] -ceq $endpoint.fixture_sha256) 'direct refusal selected archives differ'
  Assert-Fixture ($result.kind -ceq 'MIR5NativeFixtureV1' -and $result.status -ceq 'failed' -and $result.case -ceq 'published-f100-forward' -and $result.source_dirty -is [bool] -and -not $result.source_dirty -and $result.source_head -cmatch '^[a-f0-9]{40}$' -and $result.input_save.sha256 -ceq $InputSha -and $result.input_save_byte_identical -is [bool] -and $result.input_save_byte_identical) 'actual direct refusal result/source differs'
  Assert-Fixture ($result.profile.sha256 -ceq $Binding.profile.sha256 -and $result.mir_archive.sha256 -ceq $endpoint.mir_sha256 -and @($result.fixtures).Count -eq 1 -and $result.fixtures[0].sha256 -ceq $endpoint.fixture_sha256) 'actual direct refusal profile/archive result differs'
  Assert-Fixture ($result.source_head -ceq $endpoint.source_revision -and $result.harness_sha256 -ceq $endpoint.harness_sha256) 'actual direct refusal source/harness differs'
  $route=$result.published_f100_forward
  Assert-Fixture ($route.stage -ceq $endpoint.target -and $route.target -ceq $endpoint.target -and $route.role -ceq 'successor' -and $route.predecessor_origin -ceq 'published-f100-4.7.10003' -and $route.protected_input_sha256 -ceq $InputSha) 'actual direct refusal route differs'
  Assert-Fixture (@($result.process_runs).Count -eq 1) 'direct refusal requires exactly one actual failed engine'
  $run=$result.process_runs[0]
  Assert-Fixture ($run.status -ceq 'interrupted' -and [IO.Path]::GetFullPath($run.stdout) -ceq $stdoutBody.path -and [IO.Path]::GetFullPath($run.ledger) -ceq $ledgerBody.path -and $run.error -ceq $result.failure -and $run.error -match '^(\[mir441-process-exit\]|fatal native production diagnostic)') 'direct refusal actual failed process differs'
  $ledger=@($ledgerBody.text -split '\r?\n'|Where-Object {-not [string]::IsNullOrWhiteSpace($_)}|ForEach-Object {Read-RefusalJson $_})
  $running=@($ledger|Where-Object {$_.Contains('process') -and $_.process.phase -ceq 'running' -and ($_.process.id -is [int] -or $_.process.id -is [long]) -and $_.process.id -gt 0})
  Assert-Fixture ($running.Count -gt 0 -and $ledger[-1].phase -ceq 'interrupted' -and $ledger[-1].timed_out -is [bool] -and -not $ledger[-1].timed_out -and $ledger[-1].error -ceq $run.error) 'direct refusal lacks a governed native start/failure'
  $header='(?m)^\s*\d+[.]\d+\s+\d{4}-\d{2}-\d{2}[^\r\n]*; Factorio '+[regex]::Escape($base)+' \('
  $format='(?m)^\s*\d+[.]\d+\s+Error[^\r\n]*Map version 1[.]0[.]0(?:-\d+)? cannot be loaded because it is lower than the minimum input version \(\d+[.]\d+[.]\d+(?:-\d+)?\)[.]\r?$'
  Assert-Fixture ($stdoutBody.text -match $header -and $stdoutBody.text -cmatch $format) 'direct refusal is not an actual native engine save-format diagnostic'
  [pscustomobject]@{target=$endpoint.target;input_sha256=$InputSha;result_sha256=$Binding.result.sha256;profile_sha256=$Binding.profile.sha256;stdout_sha256=$Binding.stdout.sha256;ledger_sha256=$Binding.ledger.sha256;engine_sha256=$engineSha;mir_sha256=$endpoint.mir_sha256;fixture_sha256=$endpoint.fixture_sha256;process_id=$running[0].process.id}
}
function Get-PublishedF100ForwardFixture([string]$Repo,[hashtable]$Profile,[string[]]$Sources,[string]$EngineData,[string]$Engine,[string]$MIRSha,[string]$Case,[string]$Stage,[string]$InputSave,[string]$InputSha) {
  Assert-Fixture ($Stage -cin @('source','bridge','f110','f210') -and $Case -ceq 'published-f100-forward') 'published F100 forward stage/case differs'
  $tuple=switch -CaseSensitive ($Stage){
    'source' {@('f100','1.0','1.0.0','4.7.10003','0.2.0','99F1CE207A04296EF7D797E4A98AA98DDE4F02EE653C9DF736AC33A676FD4F70')}
    'bridge' {@('f110','1.1','1.1.110','4.7.11003','0.3.0','B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1')}
    'f110' {@('f110','1.1','1.1.110','5.0.11000','0.4.0','B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1')}
    'f210' {@('f210','2.1','2.1.23','5.0.21000','0.5.0','8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38')}
  }
  $target,$line,$baseVersion,$mirVersion,$fixtureVersion,$engineSha=$tuple
  $refusalReadback=$null
  Assert-Fixture ($InputSave -and $InputSha -cmatch '^[A-Fa-f0-9]{64}$' -and $Profile.protected_source_sha256 -ceq $InputSha.ToUpperInvariant()) 'published F100 forward requires its exact protected input'
  if($Stage -ceq 'source'){
    Assert-Fixture ($InputSha.ToUpperInvariant() -ceq '219EF20F63B4A85FA2386BD50A81228B28F006D9731F24E069A657BB13F45811' -and $MIRSha.ToUpperInvariant() -ceq 'C04F3543EBF99D2B76B2C9193EA0886381B7CDDF2F2C1610310E7961B24BE0E1') 'published F100 original source/MIR pin differs'
  }elseif($Stage -ceq 'bridge'){
    Assert-Fixture ($MIRSha.ToUpperInvariant() -ceq '66C127D8BFC1919FA88F19D2D9B3047316A1B90401CAA05A6D05979B7A099D1E') 'published F100 bridge requires exact published MIR'
    $refusalReadback=Read-PublishedF100DirectRefusal -Repo $Repo -Binding $Profile.engine_bridge_refusal -InputSha $InputSha.ToUpperInvariant()
  }
  Assert-Fixture ($Profile.schema -eq 1 -and $Profile.kind -ceq 'published-f100-forward' -and $Profile.stage -ceq $Stage -and $Profile.target -ceq $target -and $Profile.factorio_line -ceq $line -and $Profile.settings_mode -ceq 'Defaults' -and $Profile.predecessor_origin -ceq 'published-f100-4.7.10003') 'published F100 forward profile metadata differs'
  $expected=@(('base|'+$baseVersion+'|True'),('more-infinite-research|'+$mirVersion+'|True'),('mir-fixture-mir5-historical-transition|'+$fixtureVersion+'|True'))
  $actual=@($Profile.mods|ForEach-Object {[string]$_.name+'|'+[string]$_.version+'|'+[string]$_.enabled})
  Assert-Fixture ($actual.Count -eq 3 -and ($actual -join "`n") -ceq ($expected -join "`n")) 'published F100 forward selected closure differs'
  $archives=$Profile.archive_sha256
  Assert-Fixture ($MIRSha -cmatch '^[A-Fa-f0-9]{64}$' -and $archives -is [Collections.IDictionary] -and $archives.Count -eq 2 -and $archives['more-infinite-research_'+$mirVersion+'.zip'] -ceq $MIRSha.ToUpperInvariant() -and $archives['mir-fixture-mir5-historical-transition_'+$fixtureVersion+'.zip'] -cmatch '^[A-F0-9]{64}$') 'published F100 forward archive pins differ'
  $base=Get-Content -LiteralPath (Join-Path $EngineData 'base/info.json') -Raw | ConvertFrom-Json -AsHashtable
  Assert-Fixture ($base.version -ceq $baseVersion -and $Profile.engine.version -ceq $baseVersion -and $Profile.engine.sha256 -ceq $engineSha -and (Get-FixtureSha $Engine) -ceq $engineSha) 'published F100 forward engine pin differs'
  Assert-Fixture ($Sources.Count -eq 1) 'published F100 forward requires one composed fixture'
  $repoRoot=(Resolve-Path -LiteralPath $Repo).Path
  $source=(Resolve-Path -LiteralPath $Sources[0]).Path
  Assert-Fixture (Test-F110PublishedCrossSourceRelativePath ([IO.Path]::GetRelativePath($repoRoot,$source))) 'published F100 forward source leaves checkout'
  $canonical=Join-Path $repoRoot ('tests/fixtures/published-f100-forward/'+$Stage)
  $members=[ordered]@{}
  foreach($name in @('info.json','stage.lua','control.lua','data-final-fixes.lua','settings-updates.lua')){$members[$name]=Join-Path $canonical $name}
  $members['fixture_control.lua']=Join-Path $repoRoot 'tests/fixtures/published-f100-forward/shared/control.lua'
  $members['fixture_data_final.lua']=Join-Path $repoRoot 'tests/fixtures/published-f100-forward/shared/data-final-fixes.lua'
  Assert-Fixture (@(Get-ChildItem -LiteralPath $source -File -Force).Count -eq 7 -and @(Get-ChildItem -LiteralPath $source -Directory -Force).Count -eq 0) 'published F100 forward membership differs'
  foreach($name in $members.Keys){
    $path=(Resolve-Path -LiteralPath (Join-Path $source $name)).Path
    $expectedPath=(Resolve-Path -LiteralPath $members[$name]).Path
    Assert-Fixture ((Test-F110PublishedCrossSourceRelativePath ([IO.Path]::GetRelativePath($source,$path))) -and (Test-F110PublishedCrossSourceRelativePath ([IO.Path]::GetRelativePath($repoRoot,$expectedPath)))) 'published F100 forward member leaves checkout/composition'
    Assert-Fixture ((Get-FixtureSha $path) -ceq (Get-FixtureSha $expectedPath)) ('published F100 forward canonical member differs: '+$name)
  }
  $info=Get-Content -LiteralPath (Join-Path $source 'info.json') -Raw|ConvertFrom-Json -AsHashtable
  Assert-Fixture ($info.name -ceq 'mir-fixture-mir5-historical-transition' -and $info.version -ceq $fixtureVersion -and $info.factorio_version -ceq $line -and (@($info.dependencies)-join "`n") -ceq (@(('base >= '+$baseVersion),('more-infinite-research = '+$mirVersion))-join "`n")) 'published F100 forward fixture info differs'
  [pscustomobject]@{source=$source;name=$info.name;version=$fixtureVersion;stage=$Stage;factorio_version=$line;target=$target;role=if($Stage -in @('f110','f210')){'successor'}else{$Stage};refusal_readback=$refusalReadback}
}
function Read-FixtureResult([string]$Text,[string]$Stage) {
  $rows=@([regex]::Matches($Text,'\[MIR5_NATIVE_FIXTURE\] RESULT (\{[^\r\n]+\})') | ForEach-Object {$_.Groups[1].Value | ConvertFrom-Json} | Where-Object {$_.case -ceq $CaseName -and $_.stage -ceq $Stage})
  Assert-Fixture ($rows.Count -eq 1 -and $rows[0].status -ceq 'passed') "missing unique passed $Stage witness for $CaseName"
  $rows[0]
}
function Read-ActiveFixtureMarker([string]$Text,[string]$Kind,[string]$Stage) {
  Assert-Fixture ($Kind -in @('repair-stress','agriculture-scale') -and $Stage -in @('prepared','start','complete')) 'active fixture marker selector differs'
  $rows=@([regex]::Matches($Text,'\[MIR5_RUNTIME_ACTIVE\] (\{[^\r\n]+\})') | ForEach-Object {$_.Groups[1].Value | ConvertFrom-Json} | Where-Object {
    [string]$_.kind -ceq $Kind -and [string]$_.stage -ceq $Stage
  })
  $expectedStatus=if($Stage -ceq 'complete'){'passed'}else{'pending'}
  Assert-Fixture ($rows.Count -eq 1 -and [string]$rows[0].status -ceq $expectedStatus) "missing unique active $Stage witness for $Kind"
  $rows[0]
}
function Test-HistoricalFixtureSaveComplete([string]$Path) {
  # Early engines do not print the later "Saving finished" message. A closed,
  # readable save with its native level member is their completion boundary;
  # the two actual native reloads below establish loadability separately.
  $stream=$null;$zip=$null
  try {
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Read)
    $root=[IO.Path]::GetFileNameWithoutExtension($Path)
    foreach($name in @('level.dat','level-init.dat')){
      $entry=$zip.GetEntry($root+'/'+$name)
      if($null -ne $entry -and $entry.Length -gt 0){return $true}
    }
    return $false
  } catch { return $false }
  finally {if($null -ne $zip){$zip.Dispose()};if($null -ne $stream){$stream.Dispose()}}
}
function Read-ConsumerResults([string]$Text,[string]$Stage) {
  $results=[ordered]@{}
  foreach($marker in $ConsumerMarkers){
    Assert-Fixture ($marker -cmatch '^[A-Z][A-Z0-9_]+$') 'consumer marker name is invalid'
    $pattern='\['+[regex]::Escape($marker)+'\] RESULT (\{[^\r\n]+\})'
    $rows=@([regex]::Matches($Text,$pattern) | ForEach-Object {$_.Groups[1].Value | ConvertFrom-Json})
    Assert-Fixture ($rows.Count -eq 1 -and $rows[0].stage -ceq $Stage) "missing unique $Stage consumer witness for $marker"
    $results[$marker]=$rows[0]
  }
  $results
}
function Get-FixtureActiveModsObserver([string]$Name,[object[]]$ProfileRows,[object[]]$FixtureInputs) {
  $name=$Name.Trim()
  if([string]::IsNullOrWhiteSpace($name)){return $null}
  $profileMatches=@($ProfileRows | Where-Object {[string]$_.name -ceq $name})
  Assert-Fixture ($profileMatches.Count -eq 1) 'ActiveModsObserver must appear exactly once in the profile'
  Assert-Fixture ([bool]$profileMatches[0].enabled) 'ActiveModsObserver must be selected exactly once'
  $sourceMatches=@($FixtureInputs | Where-Object {[string]$_.name -ceq $name})
  Assert-Fixture ($sourceMatches.Count -eq 1) 'ActiveModsObserver must be a verified FixtureSources input'
  $source=$sourceMatches[0]
  Assert-Fixture ([string]$profileMatches[0].version -ceq [string]$source.version) 'ActiveModsObserver selected version differs from verified FixtureSources input'
  Assert-Fixture ([string]$source.sha256 -cmatch '^[a-fA-F0-9]{64}$') 'ActiveModsObserver verified archive hash is invalid'
  [ordered]@{name=[string]$source.name;version=[string]$source.version;source=[string]$source.source;archive=[string]$source.archive;sha256=[string]$source.sha256}
}
function Assert-ActiveFixtureSelection([string]$Kind,[object[]]$ProfileRows,[object[]]$MirRows) {
  Assert-Fixture ($Kind -in @('repair-stress','agriculture-scale')) 'active seed kind differs'
  Assert-Fixture ($MirRows.Count -eq 1) 'active seed MIR role differs'
  $selector=if($Kind -ceq 'repair-stress'){'mir-fixture-mir5-repair-stress-active'}else{'mir-fixture-mir5-agriculture-scale-active'}
  $selected=@($ProfileRows | Where-Object {[string]$_.name -ceq $selector -and [bool]$_.enabled})
  Assert-Fixture ($selected.Count -eq 1 -and [string]$selected[0].version -ceq '0.1.0') 'active seed selector differs'
  $baseFixture=if($Kind -ceq 'repair-stress'){'mir-fixture-mir5-repair-stress'}else{'mir-fixture-mir5-agriculture-scale'}
  $expectedBaseVersion=if($Kind -ceq 'repair-stress'){
    if([string]$MirRows[0].version -ceq '4.7.21002'){'0.1.0'}elseif([string]$MirRows[0].version -ceq '5.0.21000'){'0.2.0'}else{''}
  }else{'0.1.0'}
  Assert-Fixture (-not [string]::IsNullOrWhiteSpace($expectedBaseVersion)) 'active repair MIR role is unsupported'
  Assert-Fixture (@($ProfileRows | Where-Object {[string]$_.name -ceq $baseFixture -and [bool]$_.enabled -and [string]$_.version -ceq $expectedBaseVersion}).Count -eq 1) 'active seed base fixture differs'
}
function Get-HistoricalFixtureTarget([string]$Target,[string]$MetadataPath) {
  $allowed=@('f013','f014','f015','f016','f017','f018','f100','f110')
  Assert-Fixture ($Target -in $allowed) 'historical target is unsupported'
  $metadata=(Resolve-Path -LiteralPath $MetadataPath).Path
  $value=Get-Content -LiteralPath $metadata -Raw|ConvertFrom-Json -AsHashtable
  Assert-Fixture ($value.kind -ceq 'MIR5HistoricalNativeFixtureV1' -and $value.schema -eq 1) 'historical fixture metadata differs'
  Assert-Fixture ([string]$value.name -ceq 'mir-fixture-mir5-historical-native' -and [string]$value.version -ceq '0.1.0') 'historical fixture identity differs'
  $selected=$value.targets[$Target]
  Assert-Fixture ($null -ne $selected) 'historical fixture lacks selected target'
  foreach($field in @('factorio_version','minimum_base','mir_version','direct','direct_effect','continuation','continuation_mode')){
    Assert-Fixture ($selected.ContainsKey($field) -and -not [string]::IsNullOrWhiteSpace([string]$selected[$field])) "historical fixture target lacks $field"
  }
  Assert-Fixture ($Target -cmatch '^f(?:013|014|015|016|017|018|100|110)$') 'historical target literal identity differs'
  foreach($field in @('direct','continuation')){
    Assert-Fixture ([string]$selected[$field] -cmatch '^[a-z0-9][a-z0-9_-]*$') "historical target $field is not a literal-safe identifier"
  }
  $sciencePolicy=''
  if($selected.ContainsKey('science_policy')){
    $sciencePolicy=[string]$selected.science_policy
    Assert-Fixture ($sciencePolicy -ceq 'all' -and $Target -in @('f017','f018','f100','f110')) 'historical science policy differs'
  }
  $directScience=@($selected.direct_science)
  Assert-Fixture ($directScience.Count -gt 0) 'historical target lacks direct science'
  foreach($name in $directScience){Assert-Fixture ([string]$name -cmatch '^[a-z0-9][a-z0-9_-]*$') 'historical direct science is not a literal-safe identifier'}
  Assert-Fixture ([double]$selected.direct_effect -gt 0 -and [double]$selected.direct_effect -le 1) 'historical target direct effect differs'
  Assert-Fixture ([string]$selected.continuation_mode -in @('numeric-witness','lab')) 'historical continuation mode differs'
  if([string]$selected.continuation_mode -ceq 'numeric-witness'){
    foreach($field in @('continuation_count','continuation_energy_ticks')){
      Assert-Fixture ($selected.ContainsKey($field) -and [double]$selected[$field] -gt 0 -and [double]$selected[$field] -eq [math]::Floor([double]$selected[$field])) "historical numeric continuation lacks $field"
    }
  }else{
    $continuationScience=@($selected.continuation_science)
    Assert-Fixture ($continuationScience.Count -gt 0) 'historical lab continuation lacks science'
    foreach($name in $continuationScience){Assert-Fixture ([string]$name -cmatch '^[a-z0-9][a-z0-9_-]*$') 'historical continuation science is not a literal-safe identifier'}
  }
  if($Target -ceq 'f018'){
    Assert-Fixture ([string]$selected.factorio_version -ceq '0.18' -and [string]$selected.minimum_base -ceq '0.18.47' -and [string]$selected.mir_version -ceq '5.0.01800') 'F018 historical target identity differs'
    Assert-Fixture ([string]$selected.direct -ceq 'recipe-prod-research_character_mining_speed-1' -and [double]$selected.direct_effect -eq 0.1) 'F018 historical direct contract differs'
    Assert-Fixture ([string]$selected.continuation -ceq 'laser-turret-speed-8' -and [string]$selected.continuation_mode -ceq 'lab') 'F018 historical continuation differs'
    Assert-Fixture ([string]$selected.continuation_settings_family -ceq 'laser-shooting-speed' -and [string]$selected.continuation_gun_speed_ammo -ceq 'laser-turret' -and [double]$selected.continuation_effect_delta -eq 0.01) 'F018 historical continuation effect differs'
    $expectedF018DirectScience=if($sciencePolicy -ceq 'all'){
      @('military-science-pack','utility-science-pack','automation-science-pack','logistic-science-pack','chemical-science-pack','production-science-pack','space-science-pack')
    }else{@('military-science-pack','utility-science-pack')}
    $expectedF018ContinuationScience=if($sciencePolicy -ceq 'all'){
      @('automation-science-pack','chemical-science-pack','logistic-science-pack','military-science-pack','utility-science-pack','production-science-pack','space-science-pack')
    }else{@('automation-science-pack','chemical-science-pack','logistic-science-pack','military-science-pack','utility-science-pack')}
    Assert-Fixture ((@($selected.direct_science) -join "`n") -ceq ($expectedF018DirectScience -join "`n")) 'F018 historical direct science differs'
    Assert-Fixture ((@($selected.continuation_science) -join "`n") -ceq ($expectedF018ContinuationScience -join "`n")) 'F018 historical continuation science differs'
  }
  [pscustomobject][ordered]@{path=$metadata;sha256=Get-FixtureSha $metadata;name=[string]$value.name;version=[string]$value.version;target=$Target;factorio_version=[string]$selected.factorio_version;minimum_base=[string]$selected.minimum_base;mir_version=[string]$selected.mir_version;science_policy=$sciencePolicy;definition=$selected}
}
function ConvertTo-HistoricalFixtureTargetLiteral($Fixture) {
  $value=$Fixture.definition
  $lines=[Collections.Generic.List[string]]::new()
  $lines.Add('return {')
  $lines.Add(('  id="{0}",' -f $Fixture.target))
  foreach($field in @('mir_version','direct','continuation','continuation_mode')){
    $lines.Add(('  {0}="{1}",' -f $field,[string]$value[$field]))
  }
  if($Fixture.science_policy -ceq 'all'){$lines.Add('  science_policy="all",')}
  $effect=[double]$value.direct_effect
  $lines.Add(('  direct_effect={0},' -f $effect.ToString('0.################',[Globalization.CultureInfo]::InvariantCulture)))
  if($value.ContainsKey('queue_api') -and [bool]$value.queue_api){$lines.Add('  queue_api=true,')}
  foreach($field in @('continuation_settings_family','continuation_gun_speed_ammo')){
    if($value.ContainsKey($field)){
      Assert-Fixture ([string]$value[$field] -cmatch '^[a-z0-9][a-z0-9_-]*$') "historical target $field is not a literal-safe identifier"
      $lines.Add(('  {0}="{1}",' -f $field,[string]$value[$field]))
    }
  }
  if($value.ContainsKey('continuation_effect_delta')){
    $continuationEffect=[double]$value.continuation_effect_delta
    Assert-Fixture ($continuationEffect -gt 0 -and $continuationEffect -le 1) 'historical continuation effect differs'
    $lines.Add(('  continuation_effect_delta={0},' -f $continuationEffect.ToString('0.################',[Globalization.CultureInfo]::InvariantCulture)))
  }
  $directScience=@($value.direct_science|ForEach-Object {'"'+[string]$_+'"'})
  $lines.Add(('  direct_science={0},' -f ('{'+($directScience -join ',')+'}')))
  if([string]$value.continuation_mode -ceq 'numeric-witness'){
    $lines.Add(('  continuation_count={0},' -f [int64]$value.continuation_count))
    $lines.Add(('  continuation_energy_ticks={0},' -f [int64]$value.continuation_energy_ticks))
  }else{
    $continuationScience=@($value.continuation_science|ForEach-Object {'"'+[string]$_+'"'})
    $lines.Add(('  continuation_science={0},' -f ('{'+($continuationScience -join ',')+'}')))
  }
  $lines.Add('}')
  ($lines -join "`n")+"`n"
}
function Assert-HistoricalFixtureArchive([string]$Archive,[string]$SourceDirectory,$Fixture) {
  Assert-Fixture (Test-Path -LiteralPath $Archive -PathType Leaf) "historical fixture archive is absent: $Archive"
  $source=(Resolve-Path -LiteralPath $SourceDirectory).Path
  $root=$Fixture.name+'_'+$Fixture.version
  $expectedInfo=[ordered]@{
    name=$Fixture.name;version=$Fixture.version;factorio_version=$Fixture.factorio_version
    dependencies=@(('base >= '+$Fixture.minimum_base),('more-infinite-research = '+$Fixture.mir_version))
  }
  $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
  try {
    $files=@($zip.Entries|Where-Object {-not $_.FullName.EndsWith('/')})
    $expected=@(@('control.lua','settings-updates.lua','data-final-fixes.lua','target.lua','target-literal.lua','info.json')|ForEach-Object {$root+'/'+$_}|Sort-Object)
    Assert-Fixture ($files.Count -eq $expected.Count -and ((@($files.FullName|Sort-Object) -join "`n") -ceq ($expected -join "`n"))) 'historical fixture archive membership differs'
    foreach($name in @('control.lua','settings-updates.lua','data-final-fixes.lua','target.lua')){
      $entry=$zip.GetEntry($root+'/'+$name);$path=Join-Path $source $name
      Assert-Fixture ($null -ne $entry -and $entry.Length -eq (Get-Item -LiteralPath $path).Length) "historical fixture member differs: $name"
      $stream=$entry.Open();try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
      Assert-Fixture ($hash -ceq (Get-FixtureSha $path)) "historical fixture source hash differs: $name"
    }
    $literal=ConvertTo-HistoricalFixtureTargetLiteral $Fixture
    $literalBytes=[Text.UTF8Encoding]::new($false).GetBytes($literal)
    $literalEntry=$zip.GetEntry($root+'/target-literal.lua')
    Assert-Fixture ($null -ne $literalEntry -and $literalEntry.Length -eq $literalBytes.Length) 'historical fixture target literal length differs'
    $literalStream=$literalEntry.Open();try{$literalHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($literalStream))}finally{$literalStream.Dispose()}
    $expectedLiteralHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($literalBytes))
    Assert-Fixture ($literalHash -ceq $expectedLiteralHash) 'historical fixture target literal hash differs'
    $infoEntry=$zip.GetEntry($root+'/info.json');Assert-Fixture ($null -ne $infoEntry -and $infoEntry.Length -le 64KB) 'historical fixture info is absent'
    $reader=[IO.StreamReader]::new($infoEntry.Open());try{$info=$reader.ReadToEnd()|ConvertFrom-Json -AsHashtable}finally{$reader.Dispose()}
    Assert-Fixture ([string]$info.name -ceq $expectedInfo.name -and [string]$info.version -ceq $expectedInfo.version -and [string]$info.factorio_version -ceq $expectedInfo.factorio_version) 'historical fixture info identity differs'
    foreach($field in @('title','author')){
      Assert-Fixture ($info.ContainsKey($field) -and $info[$field] -is [string] -and -not [string]::IsNullOrWhiteSpace($info[$field])) "historical fixture info $field must be a nonempty string"
    }
    Assert-Fixture ((@($info.dependencies) -join "`n") -ceq ($expectedInfo.dependencies -join "`n")) 'historical fixture dependencies differ'
  } finally {$zip.Dispose()}
}
function Get-HistoricalTransitionFixtureTarget([string]$Target,[string]$MetadataPath,[string]$Stage) {
  $expectedTargets=[ordered]@{
    f013=@{factorio_version='0.13';published_mir_version='4.7.01302';mir_version='5.0.01300'}
    f014=@{factorio_version='0.14';published_mir_version='4.7.01402';mir_version='5.0.01400'}
    f015=@{factorio_version='0.15';published_mir_version='4.7.01502';mir_version='5.0.01500'}
    f016=@{factorio_version='0.16';published_mir_version='4.7.01602';mir_version='5.0.01600'}
    f017=@{factorio_version='0.17';published_mir_version='4.7.01702';mir_version='5.0.01700'}
    f018=@{factorio_version='0.18';published_mir_version='1.8.0';mir_version='5.0.01800'}
    f100=@{factorio_version='1.0';published_mir_version='4.7.10002';mir_version='5.0.10000'}
    f110=@{factorio_version='1.1';published_mir_version='4.7.11002';mir_version='5.0.11000'}
  }
  $metadata=(Resolve-Path -LiteralPath $MetadataPath).Path
  $value=Get-Content -LiteralPath $metadata -Raw|ConvertFrom-Json -AsHashtable
  Assert-Fixture ($value.kind -ceq 'MIR5HistoricalTransitionFixtureV1' -and $value.schema -eq 1) 'historical transition fixture metadata differs'
  Assert-Fixture ([string]$value.name -ceq 'mir-fixture-mir5-historical-transition' -and [string]$value.version -ceq '0.1.0') 'historical transition fixture identity differs'
  $predecessorRelease=$null
  if($value.ContainsKey('predecessor_release')){
    Assert-Fixture ($value.predecessor_release -is [string] -and $value.predecessor_release -ceq 'v4.7.3') 'historical transition predecessor release is unsupported'
    Assert-Fixture ($value.ContainsKey('published_release_id') -and (($value.published_release_id -is [int]) -or ($value.published_release_id -is [long])) -and [long]$value.published_release_id -eq 422732162) 'historical transition published release id differs'
    Assert-Fixture ($value.ContainsKey('published_tag_source') -and $value.published_tag_source -is [string] -and $value.published_tag_source -ceq '8643cc91bc915e008556a5315dbb0a743247e7ab') 'historical transition published tag source differs'
    $predecessorRelease=[string]$value.predecessor_release
    $expected473TargetSets=[ordered]@{
      'f013,f014,f015,f016'=[ordered]@{
        f013=@{factorio_version='0.13';published_mir_version='4.7.01303';mir_version='5.0.01300';published_archive_sha256='3918B10A0902FABD09BEA6D1F0E7EFF06B20B84F3D8CC5EC73E36FEDAAE64D4D'}
        f014=@{factorio_version='0.14';published_mir_version='4.7.01403';mir_version='5.0.01400';published_archive_sha256='85C7798BD6DC80FAA021AB0F33519B57A740B8D3969E695A82BA55634BA1C87A'}
        f015=@{factorio_version='0.15';published_mir_version='4.7.01503';mir_version='5.0.01500';published_archive_sha256='0F8DD4DD21B8D1542FF5EDF96FDC38F75C9AB3CE577DF29C5E9DE99E0643B510'}
        f016=@{factorio_version='0.16';published_mir_version='4.7.01603';mir_version='5.0.01600';published_archive_sha256='DAC63B9B14278C952B1020F9AE600C1437A9812C79CBBA17DE3CB15AF0CED6BD'}
      }
      'f017,f100'=[ordered]@{
        f017=@{factorio_version='0.17';minimum_base='0.17.79';published_mir_version='4.7.01703';mir_version='5.0.01700';published_archive_sha256='9BCF1813BBDCBBD90088D74672CEF639FBC96689604673E529CF3AA8FC8D89AF'}
        f100=@{factorio_version='1.0';minimum_base='1.0.0';published_mir_version='4.7.10003';mir_version='5.0.10000';published_archive_sha256='C04F3543EBF99D2B76B2C9193EA0886381B7CDDF2F2C1610310E7961B24BE0E1'}
      }
    }
    $targetSet=@($value.targets.Keys|Sort-Object)-join ','
    Assert-Fixture ($expected473TargetSets.Contains($targetSet)) '4.7.3 historical transition target set differs'
    $expectedTargets=$expected473TargetSets[$targetSet]
  }
  $allowed=@($expectedTargets.Keys)
  Assert-Fixture ($Target -in $allowed) 'historical transition target is unsupported'
  Assert-Fixture ($Stage -in @('published','mir5')) 'historical transition stage is unsupported'
  $selected=$value.targets[$Target]
  Assert-Fixture ($null -ne $selected) 'historical transition fixture lacks selected target'
  foreach($field in @('factorio_version','minimum_base','published_mir_version','mir_version','published_archive_sha256','direct','direct_effect','successor_mode')){
    Assert-Fixture ($selected.ContainsKey($field) -and -not [string]::IsNullOrWhiteSpace([string]$selected[$field])) "historical transition target lacks $field"
  }
  $expected=$expectedTargets[$Target]
  Assert-Fixture ([string]$selected.factorio_version -ceq [string]$expected.factorio_version) 'historical transition factorio version differs'
  if($expected.ContainsKey('minimum_base')){Assert-Fixture ([string]$selected.minimum_base -ceq [string]$expected.minimum_base) 'historical transition minimum base differs'}
  Assert-Fixture ([string]$selected.published_mir_version -ceq [string]$expected.published_mir_version -and [string]$selected.mir_version -ceq [string]$expected.mir_version) 'historical transition MIR versions differ'
  Assert-Fixture ([string]$selected.published_archive_sha256 -cmatch '^[A-Fa-f0-9]{64}$') 'historical transition published archive hash differs'
  if($null -ne $predecessorRelease){Assert-Fixture ([string]$selected.published_archive_sha256 -ceq [string]$expected.published_archive_sha256) 'historical transition published archive hash differs'}
  Assert-Fixture ([string]$selected.direct -cmatch '^[a-z0-9][a-z0-9_-]*$') 'historical transition direct is not a literal-safe identifier'
  $directScience=@($selected.direct_science)
  Assert-Fixture ($directScience.Count -gt 0) 'historical transition target lacks direct science'
  foreach($name in $directScience){Assert-Fixture ([string]$name -cmatch '^[a-z0-9][a-z0-9_-]*$') 'historical transition direct science is not a literal-safe identifier'}
  Assert-Fixture ([double]$selected.direct_effect -gt 0 -and [double]$selected.direct_effect -le 1) 'historical transition direct effect differs'
  $expectedMode=if($Target -in @('f013','f014')){'preservation-only'}else{'lab'}
  Assert-Fixture ([string]$selected.successor_mode -ceq $expectedMode) 'historical transition successor mode differs'
  $queue=[bool]($selected.ContainsKey('queue_api') -and $selected.queue_api)
  if($expectedMode -ceq 'lab'){
    Assert-Fixture ($selected.ContainsKey('partial_progress') -and [double]$selected['partial_progress'] -gt 0 -and [double]$selected['partial_progress'] -lt 1) 'historical transition partial progress differs'
  }else{
    Assert-Fixture (-not $selected.ContainsKey('partial_progress') -and -not $queue -and -not $selected.ContainsKey('queue_probe')) 'preservation-only historical transition declares successor state'
  }
  if($queue){
    Assert-Fixture ($selected.ContainsKey('queue_probe') -and [string]$selected['queue_probe'] -cmatch '^[a-z0-9][a-z0-9_-]*$') 'historical transition queue probe is not a literal-safe identifier'
  }elseif($selected.ContainsKey('queue_probe')){throw '[mir5-native-fixture] historical transition non-queue target declares a queue probe'}
  if($Target -ceq 'f018'){
    Assert-Fixture ([string]$selected.published_archive_sha256 -ceq 'D785E6EBE7A72E6E9F01A3F89774A6AA30479430410447F603FEF1E0B9BD7B24') 'F018 historical transition published archive hash differs'
    Assert-Fixture ([string]$selected.mir5_archive_sha256 -ceq '7803FC661DEFA441D1E9D508D1CA80029E619201BBECB0BF113D60D3D3ABEEB9') 'F018 historical transition MIR5 archive hash differs'
    Assert-Fixture ($selected.ContainsKey('foreign_force_name') -and [string]$selected.foreign_force_name -ceq 'mir5-historical-transition-foreign') 'F018 historical transition foreign force differs'
    Assert-Fixture ($selected.ContainsKey('foreign_saved_progress') -and [double]$selected.foreign_saved_progress -gt 0 -and [double]$selected.foreign_saved_progress -lt 1) 'F018 historical transition foreign progress differs'
    Assert-Fixture ([string]$selected.published_unit_count_formula -ceq '8000 * 2^(L-1)' -and [string]$selected.mir5_unit_count_formula -ceq '1*(8000*2^(L-1))') 'F018 historical transition cost contract differs'
  }elseif($selected.ContainsKey('foreign_force_name') -or $selected.ContainsKey('foreign_saved_progress') -or $selected.ContainsKey('published_unit_count_formula') -or $selected.ContainsKey('mir5_unit_count_formula')){
    throw '[mir5-native-fixture] non-F018 historical transition declares F018-only state'
  }
  $version=if($Stage -ceq 'published'){[string]$selected.published_mir_version}else{[string]$selected.mir_version}
  [pscustomobject][ordered]@{path=$metadata;sha256=Get-FixtureSha $metadata;name=[string]$value.name;version=[string]$value.version;target=$Target;stage=$Stage;factorio_version=[string]$selected.factorio_version;minimum_base=[string]$selected.minimum_base;mir_version=$version;definition=$selected}
}
function ConvertTo-HistoricalTransitionFixtureTargetLiteral($Fixture) {
  $value=$Fixture.definition
  $lines=[Collections.Generic.List[string]]::new()
  $lines.Add('return {')
  $lines.Add(('  id="{0}",' -f [string]$Fixture.target))
  foreach($field in @('stage','mir_version')){$lines.Add(('  {0}="{1}",' -f $field,[string]$Fixture.$field))}
  $lines.Add(('  direct="{0}",' -f [string]$value.direct))
  $lines.Add(('  direct_effect={0},' -f ([double]$value.direct_effect).ToString('0.################',[Globalization.CultureInfo]::InvariantCulture)))
  $lines.Add(('  successor_mode="{0}",' -f [string]$value.successor_mode))
  if([string]$value.successor_mode -ceq 'lab'){$lines.Add(('  partial_progress={0},' -f ([double]$value.partial_progress).ToString('0.################',[Globalization.CultureInfo]::InvariantCulture)))}
  $science=@($value.direct_science|ForEach-Object {'"'+[string]$_+'"'})
  $lines.Add(('  direct_science={0},' -f ('{'+($science -join ',')+'}')))
  if($value.ContainsKey('queue_api') -and [bool]$value.queue_api){
    $lines.Add('  queue_api=true,')
    $lines.Add(('  queue_probe="{0}",' -f [string]$value.queue_probe))
  }
  if([string]$Fixture.target -ceq 'f018'){
    $lines.Add(('  foreign_force_name="{0}",' -f [string]$value.foreign_force_name))
    $lines.Add(('  foreign_saved_progress={0},' -f ([double]$value.foreign_saved_progress).ToString('0.################',[Globalization.CultureInfo]::InvariantCulture)))
  }
  $lines.Add('}')
  ($lines -join "`n")+"`n"
}
function Assert-HistoricalTransitionFixtureArchive([string]$Archive,[string]$SourceDirectory,$Fixture) {
  Assert-Fixture (Test-Path -LiteralPath $Archive -PathType Leaf) "historical transition fixture archive is absent: $Archive"
  $source=(Resolve-Path -LiteralPath $SourceDirectory).Path
  $root=$Fixture.name+'_'+$Fixture.version
  $expectedInfo=[ordered]@{
    name=$Fixture.name;version=$Fixture.version;factorio_version=$Fixture.factorio_version
    dependencies=@(('base >= '+$Fixture.minimum_base),('more-infinite-research = '+$Fixture.mir_version))
  }
  $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
  try {
    $files=@($zip.Entries|Where-Object {-not $_.FullName.EndsWith('/')})
    $expected=@(@('control.lua','settings-updates.lua','data-final-fixes.lua','target.lua','target-literal.lua','info.json')|ForEach-Object {$root+'/'+$_}|Sort-Object)
    Assert-Fixture ($files.Count -eq $expected.Count -and ((@($files.FullName|Sort-Object) -join "`n") -ceq ($expected -join "`n"))) 'historical transition fixture archive membership differs'
    foreach($name in @('control.lua','settings-updates.lua','data-final-fixes.lua','target.lua')){
      $entry=$zip.GetEntry($root+'/'+$name);$path=Join-Path $source $name
      Assert-Fixture ($null -ne $entry -and $entry.Length -eq (Get-Item -LiteralPath $path).Length) "historical transition fixture member differs: $name"
      $stream=$entry.Open();try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
      Assert-Fixture ($hash -ceq (Get-FixtureSha $path)) "historical transition fixture source hash differs: $name"
    }
    $literal=ConvertTo-HistoricalTransitionFixtureTargetLiteral $Fixture
    $literalBytes=[Text.UTF8Encoding]::new($false).GetBytes($literal)
    $literalEntry=$zip.GetEntry($root+'/target-literal.lua')
    Assert-Fixture ($null -ne $literalEntry -and $literalEntry.Length -eq $literalBytes.Length) 'historical transition fixture target literal length differs'
    $literalStream=$literalEntry.Open();try{$literalHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($literalStream))}finally{$literalStream.Dispose()}
    $expectedLiteralHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($literalBytes))
    Assert-Fixture ($literalHash -ceq $expectedLiteralHash) 'historical transition fixture target literal hash differs'
    $infoEntry=$zip.GetEntry($root+'/info.json');Assert-Fixture ($null -ne $infoEntry -and $infoEntry.Length -le 64KB) 'historical transition fixture info is absent'
    $reader=[IO.StreamReader]::new($infoEntry.Open());try{$info=$reader.ReadToEnd()|ConvertFrom-Json -AsHashtable}finally{$reader.Dispose()}
    Assert-Fixture ([string]$info.name -ceq $expectedInfo.name -and [string]$info.version -ceq $expectedInfo.version -and [string]$info.factorio_version -ceq $expectedInfo.factorio_version) 'historical transition fixture info identity differs'
    foreach($field in @('title','author')){
      Assert-Fixture ($info.ContainsKey($field) -and $info[$field] -is [string] -and -not [string]::IsNullOrWhiteSpace($info[$field])) "historical transition fixture info $field must be a nonempty string"
    }
    Assert-Fixture ((@($info.dependencies) -join "`n") -ceq ($expectedInfo.dependencies -join "`n")) 'historical transition fixture dependencies differ'
  } finally {$zip.Dispose()}
}
function New-HistoricalFixtureServerSettings([string]$Path,[string]$EngineData,[string]$FactorioVersion) {
  Assert-Fixture ($FactorioVersion -in @('0.13','0.14','0.15','0.16','0.17','0.18','1.0','1.1')) 'historical server target differs'
  $settings=Get-Content -LiteralPath (Join-Path $EngineData 'server-settings.example.json') -Raw | ConvertFrom-Json -AsHashtable
  $settings.name='MIR private historical fixture'
  $settings.description=''
  $settings.visibility=if($FactorioVersion -ceq '0.13'){'hidden'}else{@{public=$false;lan=$false}}
  foreach($field in @('username','password','token')){$settings[$field]=''}
  foreach($field in @('verify_user_identity','require_user_verification')){
    if($settings.ContainsKey($field)){$settings[$field]=$false}
  }
  $settings.auto_pause=$false
  [IO.File]::WriteAllText($Path,($settings|ConvertTo-Json -Depth 10)+"`n",[Text.UTF8Encoding]::new($false))
  $arguments=@('--server-settings',$Path)
  # F013 uses a CLI switch rather than the later auto_pause JSON field. Its
  # binary has no --bind option; hidden visibility keeps it unadvertised.
  if($FactorioVersion -ceq '0.13'){$arguments+='--no-auto-pause'}
  else{$arguments+=@('--bind','127.0.0.1')}
  [pscustomobject][ordered]@{path=$Path;sha256=Get-FixtureSha $Path;visibility=$settings.visibility;auto_pause=$false;arguments=$arguments}
}
function New-ModernFixtureServerSettings([string]$Path,[string]$EngineData) {
  $template=Join-Path $EngineData 'server-settings.example.json'
  $settings=Get-Content -LiteralPath $template -Raw | ConvertFrom-Json -AsHashtable
  $settings.name='MIR private native fixture'
  $settings.description=''
  $settings.visibility=@{public=$false;lan=$false}
  $settings.username='';$settings.password='';$settings.token='';$settings.game_password=''
  $settings.require_user_verification=$false
  $settings.auto_pause=$false
  $settings.autosave_interval=0
  $settings.max_players=1
  [IO.File]::WriteAllText($Path,($settings | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
  [pscustomobject][ordered]@{template=$template;template_sha256=Get-FixtureSha $template;path=$Path;sha256=Get-FixtureSha $Path}
}
function Invoke-FixtureStage([string]$Name,[string[]]$StageArguments,[scriptblock]$Completion=$null) {
  $live=Join-Path $writeData 'factorio-current.log'
  if(Test-Path -LiteralPath $live){Remove-Item -LiteralPath $live}
  $arguments=@('--config',$config,'--mod-directory',$activation.library,'--no-log-rotation')
  if(-not $historicalProcess){
    $arguments+='--disable-audio'
  }elseif(-not $historical -or $historicalFixture.factorio_version -notin @('0.13','0.14')){
    # Keep the older-engine exception tied to the historical fixture metadata;
    # the F110 published source leg is an explicit 1.1 process-mode caller.
    $arguments+='--disable-audio'
  }
  $arguments+=$StageArguments
  Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $arguments
  # Completed host parsing/interop allocations need not occupy commit while a
  # later native stage waits for admission. Keep every governor limit intact.
  [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect()
  $native=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments $arguments -TimeoutSeconds $TimeoutSeconds -CompletionPredicate $Completion -AdmissionWaitSeconds $AdmissionWaitSeconds -AdmissionPhase ('fixture-'+$Name)
  $log=Join-Path $resources.root ($Name+'.factorio.log')
  Assert-Fixture (Test-Path -LiteralPath $live -PathType Leaf) "$Name native log absent"
  Copy-Item -LiteralPath $live -Destination $log
  foreach($path in @($log,$native.stdout,$native.stderr)){Assert-FixtureLog ([IO.File]::ReadAllText($path))}
  Assert-Fixture ($native.result.passed -and -not $native.result.timed_out) "$Name process failed"
  if($null -ne $Completion){
    Assert-Fixture $native.result.completion_predicate_observed "$Name exited before a live completion"
  }else{
    Assert-Fixture ($native.result.exit_code -eq 0) "$Name natural exit was not zero"
  }
  [ordered]@{process=$native;log=$log;log_sha256=Get-FixtureSha $log;loaded_selection=Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -LatestInvocation -ActiveModsObserver $activeModsObserverName}
}

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$library=(Resolve-Path -LiteralPath $ArchiveLibrary).Path
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
$activeModsObserverName=$ActiveModsObserver.Trim()
$engineData=Join-Path (Get-Item -LiteralPath $engine).Directory.Parent.Parent.FullName 'data'
$historical=-not [string]::IsNullOrWhiteSpace($HistoricalTarget)
$historicalTransition=-not [string]::IsNullOrWhiteSpace($HistoricalTransitionStage)
$f110PublishedCrossSource=[bool]$F110PublishedCrossSource
$f110SameEditionSuccessor=[bool]$F110SameEditionSuccessor
$laserTransition=-not [string]::IsNullOrWhiteSpace($F100F110LaserStage)
$publishedF100Forward=-not [string]::IsNullOrWhiteSpace($PublishedF100ForwardStage)
Assert-Fixture (-not ($f110PublishedCrossSource -and $f110SameEditionSuccessor)) 'select only one F110 transition stage'
$historicalProcess=$historical -or $f110PublishedCrossSource -or $f110SameEditionSuccessor -or $laserTransition
if($publishedF100Forward){$historicalProcess=$PublishedF100ForwardStage -cne 'f210'}
$historicalProcessVersion=''
$historicalFixture=$null
$activeSeed=[bool]$ActiveSeedOnly
if($activeSeed){
  Assert-Fixture ($ActiveSeedKind -in @('repair-stress','agriculture-scale')) 'active seed kind differs'
  Assert-Fixture (-not $historical -and -not $historicalTransition -and -not $f110PublishedCrossSource -and -not $f110SameEditionSuccessor -and -not $laserTransition -and -not $publishedF100Forward -and -not $CreateOnly -and -not $MIRAbsent) 'active seed requires a modern installed-MIR fixture run'
  Assert-Fixture (-not $InputSavePath -and -not $ExpectedInputSaveSha256) 'active seed must begin from its own fresh fixture save'
  $expectedCase=if($ActiveSeedKind -ceq 'repair-stress'){'repair-stress-active'}else{'agriculture-scale-active'}
  Assert-Fixture ($CaseName -ceq $expectedCase) 'active seed case differs'
}
if($publishedF100Forward){
  Assert-Fixture (-not $historical -and -not $historicalTransition -and -not $f110PublishedCrossSource -and -not $f110SameEditionSuccessor -and -not $laserTransition -and -not $CreateOnly -and -not $MIRAbsent -and -not $activeSeed -and -not $ActiveSeedKind -and -not $activeModsObserverName -and $ConsumerMarkers.Count -eq 0 -and -not $HistoricalFixtureMetadataPath -and -not $HistoricalTransitionFixtureMetadataPath) 'published F100 forward modes are exclusive'
  $historicalProcessVersion=if($PublishedF100ForwardStage -ceq 'source'){'1.0'}elseif($PublishedF100ForwardStage -ceq 'f210'){''}else{'1.1'}
}elseif($laserTransition){
  Assert-Fixture (-not $historical -and -not $historicalTransition -and -not $f110PublishedCrossSource -and -not $f110SameEditionSuccessor -and -not $CreateOnly -and -not $MIRAbsent -and -not $activeSeed -and -not $ActiveSeedKind -and -not $activeModsObserverName -and $ConsumerMarkers.Count -eq 0 -and -not $HistoricalFixtureMetadataPath -and -not $HistoricalTransitionFixtureMetadataPath) 'laser transition modes are exclusive'
  $historicalProcessVersion=if($F100F110LaserStage -ceq 'source'){'1.0'}else{'1.1'}
}elseif($f110PublishedCrossSource -or $f110SameEditionSuccessor){
  $historicalProcessVersion='1.1'
}elseif($historicalTransition){
  Assert-Fixture $historical 'historical transition requires a historical target'
  Assert-Fixture (-not $CreateOnly -and -not $MIRAbsent) 'historical transition requires an installed MIR predecessor or successor'
  Assert-Fixture ($CaseName -ceq 'historical-transition' -and $ConsumerMarkers.Count -eq 0) 'historical transition uses its own marker without modern consumers'
  Assert-Fixture ([string]::IsNullOrWhiteSpace($activeModsObserverName)) 'historical transition does not select a modern active-mod observer'
  Assert-Fixture ([string]::IsNullOrWhiteSpace($HistoricalFixtureMetadataPath)) 'historical transition must not use fresh historical metadata'
  Assert-Fixture ($FixtureSources.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($HistoricalTransitionFixtureMetadataPath)) 'historical transition requires one source and its metadata'
  if($HistoricalTransitionStage -ceq 'published'){
    Assert-Fixture (-not $InputSavePath -and -not $ExpectedInputSaveSha256) 'published historical transition must create a fresh predecessor save'
  }else{
    Assert-Fixture ($InputSavePath -and $ExpectedInputSaveSha256 -cmatch '^[a-fA-F0-9]{64}$') 'MIR5 historical transition requires an immutable predecessor save hash'
  }
  $historicalFixture=Get-HistoricalTransitionFixtureTarget -Target $HistoricalTarget -MetadataPath $HistoricalTransitionFixtureMetadataPath -Stage $HistoricalTransitionStage
  $historicalProcessVersion=$historicalFixture.factorio_version
  $base=Get-Content -LiteralPath (Join-Path $engineData 'base/info.json') -Raw|ConvertFrom-Json -AsHashtable
  Assert-Fixture ([string]$base.version -ceq $historicalFixture.minimum_base) 'historical transition engine base differs from target metadata'
}elseif($historical){
  Assert-Fixture (-not $CreateOnly -and -not $MIRAbsent -and -not $InputSavePath -and -not $ExpectedInputSaveSha256) 'historical fixtures require a fresh full run'
  Assert-Fixture ($CaseName -ceq 'historical-native' -and $ConsumerMarkers.Count -eq 0) 'historical fixtures use their own marker without modern consumers'
  Assert-Fixture ([string]::IsNullOrWhiteSpace($activeModsObserverName)) 'historical fixtures do not select a modern active-mod observer'
  Assert-Fixture ([string]::IsNullOrWhiteSpace($HistoricalTransitionFixtureMetadataPath)) 'fresh historical fixture must not use transition metadata'
  Assert-Fixture ($FixtureSources.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($HistoricalFixtureMetadataPath)) 'historical fixtures require one source and its metadata'
  $historicalFixture=Get-HistoricalFixtureTarget -Target $HistoricalTarget -MetadataPath $HistoricalFixtureMetadataPath
  $historicalProcessVersion=$historicalFixture.factorio_version
  $base=Get-Content -LiteralPath (Join-Path $engineData 'base/info.json') -Raw|ConvertFrom-Json -AsHashtable
  Assert-Fixture ([string]$base.version -ceq $historicalFixture.minimum_base) 'historical fixture engine base differs from target metadata'
}else{
  Assert-Fixture ([string]::IsNullOrWhiteSpace($HistoricalFixtureMetadataPath) -and [string]::IsNullOrWhiteSpace($HistoricalTransitionFixtureMetadataPath)) 'modern fixture runs do not accept historical metadata'
}
$inputSave=$null
if($InputSavePath -or $ExpectedInputSaveSha256){
  Assert-Fixture (-not $f110PublishedCrossSource -and -not $CreateOnly -and -not $activeSeed -and -not $MIRAbsent -and $InputSavePath -and $ExpectedInputSaveSha256 -cmatch '^[a-fA-F0-9]{64}$') 'an input save requires a full fixture run and exact hash'
  $inputSave=(Resolve-Path -LiteralPath $InputSavePath).Path
  Assert-Fixture ((Test-Path -LiteralPath $inputSave -PathType Leaf) -and [IO.Path]::GetExtension($inputSave) -ceq '.zip') 'input save is not a ZIP file'
  Assert-Fixture ((Get-FixtureSha $inputSave) -ceq $ExpectedInputSaveSha256.ToUpperInvariant()) 'input save hash differs'
}
$identityModule=New-Module -Name MIR5FixtureIdentity -ArgumentList (Join-Path $repo 'tools/lib/validation/ImmutableInputStaging.ps1') -ScriptBlock {
  param($Path)
  . $Path
  Export-ModuleMember -Function Get-MIRImmutableInputSha256,Get-MIRImmutableInputFileIdentity,Assert-MIRCheckoutHardLinkBoundary
}
Import-Module $identityModule -Force
. (Join-Path $repo 'tools/lib/validation/DirectLibraryStartupMeasurement.ps1')
$profile=(Resolve-Path -LiteralPath $ProfilePath).Path
$profileDefinition=Get-Content -LiteralPath $profile -Raw | ConvertFrom-Json -AsHashtable
$rows=@($profileDefinition.mods)
$publishedF100Fixture=$null
if($publishedF100Forward){
  $publishedF100Fixture=Get-PublishedF100ForwardFixture -Repo $repo -Profile $profileDefinition -Sources $FixtureSources -EngineData $engineData -Engine $engine -MIRSha $ExpectedMIRArchiveSha256 -Case $CaseName -Stage $PublishedF100ForwardStage -InputSave $InputSavePath -InputSha $ExpectedInputSaveSha256
}
$laserFixture=$null
if($laserTransition){
  $laserFixture=Get-F100F110LaserFixture -Repo $repo -Profile $profileDefinition -Sources $FixtureSources -EngineData $engineData -Engine $engine -MIRSha $ExpectedMIRArchiveSha256 -Case $CaseName -Stage $F100F110LaserStage -OtherModes:$false -InputSave $InputSavePath -InputSha $ExpectedInputSaveSha256
}
$inventory=@(Get-MIRLibraryInventory -LibraryDirectory $library -EngineDataDirectory $engineData)
$mirRows=@($rows | Where-Object {$_.name -ceq 'more-infinite-research' -and $_.enabled})
$f110CrossSourceFixture=$null
if($f110PublishedCrossSource -or $f110SameEditionSuccessor){
  $f110CrossSourceFixture=Get-F110PublishedCrossSourceFixture -Repo $repo -ProfileDefinition $profileDefinition -ProfileRows $rows -Sources $FixtureSources -EngineData $engineData -Engine $engine -ExpectedMIRSha256 $ExpectedMIRArchiveSha256 -Case $CaseName -Historical $historical -HistoricalTransition $historicalTransition -Create $CreateOnly -Absent $MIRAbsent -Active $activeSeed -ActiveKind $ActiveSeedKind -InputSave $InputSavePath -InputSaveSha256 $ExpectedInputSaveSha256 -Observer $activeModsObserverName -Markers $ConsumerMarkers -HistoricalTarget $HistoricalTarget -HistoricalMetadata $HistoricalFixtureMetadataPath -TransitionStage $HistoricalTransitionStage -TransitionMetadata $HistoricalTransitionFixtureMetadataPath -SameEditionSuccessor $f110SameEditionSuccessor
}
$mir=@()
if($MIRAbsent){
  Assert-Fixture ($mirRows.Count -eq 0 -and $ExpectedMIRArchiveSha256 -ceq '') 'MIR absence requires a profile without MIR or its hash'
}else{
  Assert-Fixture ($mirRows.Count -eq 1 -and $ExpectedMIRArchiveSha256 -match '^[a-fA-F0-9]{64}$') 'one pinned MIR selection is required'
  $mir=@($inventory | Where-Object {$_.name -ceq 'more-infinite-research' -and $_.version -ceq $mirRows[0].version})
  Assert-Fixture ($mir.Count -eq 1 -and (Get-FixtureSha $mir[0].path) -ceq $ExpectedMIRArchiveSha256.ToUpperInvariant()) 'MIR archive hash differs'
  if($historicalTransition){
    Assert-Fixture ([string]$mirRows[0].version -ceq [string]$historicalFixture.mir_version) 'historical transition profile MIR version differs'
    if($HistoricalTransitionStage -ceq 'published'){
      Assert-Fixture ($ExpectedMIRArchiveSha256.ToUpperInvariant() -ceq [string]$historicalFixture.definition.published_archive_sha256) 'historical transition published archive hash differs'
    }elseif($historicalFixture.target -ceq 'f018'){
      Assert-Fixture ($ExpectedMIRArchiveSha256.ToUpperInvariant() -ceq [string]$historicalFixture.definition.mir5_archive_sha256) 'F018 historical transition MIR5 archive hash differs'
    }
  }
}
if($activeSeed){Assert-ActiveFixtureSelection $ActiveSeedKind $rows $mirRows}
$fixtureInputs=@();$fixtureBindings=@()
if($historical){
  $source=(Resolve-Path -LiteralPath $FixtureSources[0]).Path
  Assert-Fixture ((Split-Path -Parent $historicalFixture.path) -ceq $source) 'historical fixture metadata is not beside its source'
  $archive=Join-Path $library ($historicalFixture.name+'_'+$historicalFixture.version+'.zip')
  if($historicalTransition){
    Assert-HistoricalTransitionFixtureArchive -Archive $archive -SourceDirectory $source -Fixture $historicalFixture
  }else{
    Assert-HistoricalFixtureArchive -Archive $archive -SourceDirectory $source -Fixture $historicalFixture
  }
  Assert-Fixture (@($rows | Where-Object {$_.enabled -and $_.name -ceq $historicalFixture.name -and $_.version -ceq $historicalFixture.version}).Count -eq 1) 'historical fixture is not selected exactly once'
  $archiveSha=Get-FixtureSha $archive
  $fixtureInputs+=@{source=$source;archive=$archive;sha256=$archiveSha}
  $fixtureBindings+=@{name=$historicalFixture.name;version=$historicalFixture.version;source=$source;archive=$archive;sha256=$archiveSha}
}else{
  foreach($source in $FixtureSources){
    $source=(Resolve-Path -LiteralPath $source).Path
    $info=Get-Content -LiteralPath (Join-Path $source 'info.json') -Raw | ConvertFrom-Json
    $archive=Join-Path $library ($info.name+'_'+$info.version+'.zip')
    Assert-MIRLibraryFixtureArchive -Archive $archive -SourceDirectory $source
    Assert-Fixture (@($rows | Where-Object {$_.enabled -and $_.name -ceq $info.name -and $_.version -ceq $info.version}).Count -eq 1) 'fixture is not selected exactly once'
    $archiveSha=Get-FixtureSha $archive
    $fixtureInputs+=@{source=$source;archive=$archive;sha256=$archiveSha}
    $fixtureBindings+=@{name=[string]$info.name;version=[string]$info.version;source=$source;archive=$archive;sha256=$archiveSha}
  }
}
if($f110PublishedCrossSource -or $f110SameEditionSuccessor){
  Assert-Fixture ($fixtureBindings.Count -eq 1 -and [string]$fixtureBindings[0].name -ceq $f110CrossSourceFixture.name -and [string]$fixtureBindings[0].version -ceq $f110CrossSourceFixture.version -and [string]$fixtureBindings[0].source -ceq $f110CrossSourceFixture.source) 'F110 published cross source fixture selection differs'
}
if($laserTransition){Assert-Fixture ($fixtureBindings.Count -eq 1 -and [string]$fixtureBindings[0].name -ceq $laserFixture.name -and [string]$fixtureBindings[0].version -ceq $laserFixture.version -and [string]$fixtureBindings[0].source -ceq $laserFixture.source) 'laser fixture selection differs'}
if($publishedF100Forward){Assert-Fixture ($fixtureBindings.Count -eq 1 -and [string]$fixtureBindings[0].name -ceq $publishedF100Fixture.name -and [string]$fixtureBindings[0].version -ceq $publishedF100Fixture.version -and [string]$fixtureBindings[0].source -ceq $publishedF100Fixture.source) 'published F100 forward fixture selection differs'}
$activeModsObserverBinding=Get-FixtureActiveModsObserver -Name $activeModsObserverName -ProfileRows $rows -FixtureInputs $fixtureBindings
$engineIdentity=Get-MIRDirectLibraryStartupEngineIdentity -FactorioBin $engine -EngineDataDirectory $engineData
$archiveHashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $library -EngineDataDirectory $engineData -BaseRows $rows -MirArchive $null
Assert-DeclaredFixtureInputs -ProfileDefinition $profileDefinition -EngineIdentity $engineIdentity -ArchiveHashes $archiveHashes
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -Mode Hook -MaxWorktrees 2 -MaxBranches 4 -MaxScanSeconds 2 -MaxEntriesPerRoot 500 | Out-Host
$resources=$null;$activation=$null;$failure=$null
$record=[ordered]@{
  kind='MIR5NativeFixtureV1';status='prepared';case=$CaseName
  source_head=[string](& git -C $repo rev-parse HEAD)
  source_dirty=(@(& git -C $repo status --porcelain=v1).Count -gt 0)
  harness_sha256=Get-FixtureSha $PSCommandPath
  native_probe_sha256=Get-FixtureSha (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
  governor_sha256=Get-FixtureSha (Join-Path $repo 'tools/lib/validation/ResourceGovernor.ps1')
  engine=$engineIdentity
  profile=@{path=$profile;sha256=Get-FixtureSha $profile};fixtures=$fixtureInputs
  historical_target=if($historical){@{id=$historicalFixture.target;metadata_path=$historicalFixture.path;metadata_sha256=$historicalFixture.sha256;factorio_version=$historicalFixture.factorio_version;minimum_base=$historicalFixture.minimum_base;mir_version=$historicalFixture.mir_version}}else{$null}
  historical_transition=if($historicalTransition){@{stage=$HistoricalTransitionStage;published_archive_sha256=[string]$historicalFixture.definition.published_archive_sha256;predecessor_mir_version=[string]$historicalFixture.definition.published_mir_version;successor_mir_version=[string]$historicalFixture.definition.mir_version}}else{$null}
  mir_archive=if($MIRAbsent){$null}else{@{path=$mir[0].path;sha256=$ExpectedMIRArchiveSha256.ToUpperInvariant()}}
  observation=if($CreateOnly){'native-create-runtime-load-only'}elseif($activeSeed){'native-active-save-preparation-only'}else{'native-fixture-production-and-two-cold-reloads'}
  input_save=if($inputSave){@{path=$inputSave;sha256=$ExpectedInputSaveSha256.ToUpperInvariant()}}else{$null}
  release_qualification=$false
}
if($laserTransition){$record.f100_f110_laser_transition=@{stage=$F100F110LaserStage;factorio_version=$historicalProcessVersion}}
if($publishedF100Forward){$record.published_f100_forward=@{stage=$PublishedF100ForwardStage;target=$publishedF100Fixture.target;role=$publishedF100Fixture.role;predecessor_origin='published-f100-4.7.10003';protected_input_sha256=$ExpectedInputSaveSha256.ToUpperInvariant()}}
if($publishedF100Forward -and $PublishedF100ForwardStage -ceq 'bridge'){$record.published_f100_forward.engine_bridge_refusal_readback=$publishedF100Fixture.refusal_readback}
try{
  # Compile the governor's native memory reader before releasing temporary
  # host allocations; its first Add-Type call otherwise occurs inside wait.
  $null=Get-MIR441PhysicalMemorySnapshot
  [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect()
  $record.initial_admission_wait=Wait-MIRDirectLibraryStartupAdmission -Policy ([pscustomobject]@{minimum_free_ram_gib=4}) -WorkRoot $OutputRoot -EstimatedPeakBytes 128MB -ExpectedPeakMemoryBytes ([int64]$ExpectedPeakMemoryMiB*1MB) -AdmissionWaitSeconds $AdmissionWaitSeconds -Phase 'fixture-initial'
  $resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB 128 -UseExactOutputRoot
  $writeData=Join-Path $resources.root 'write-data'
  [IO.Directory]::CreateDirectory((Join-Path $writeData 'saves')) | Out-Null
  $config=Join-Path $resources.root 'config.ini'
  if($historicalProcess){
    # Older engines use the retained direct-library minimal form.  Do not
    # inherit modern option keys into F013--F110.
    $historicalConfig=@('[path]',"read-data=$($engineData.Replace('\','/'))","write-data=$($writeData.Replace('\','/'))",'', '[other]','check-updates=false','enable-new-mods=false') -join "`n"
    [IO.File]::WriteAllText($config,$historicalConfig+"`n",[Text.UTF8Encoding]::new($false))
  }else{
    New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $engineData -WriteDataDirectory $writeData
  }
  $activationArguments=@{LibraryDirectory=$library;EngineDataDirectory=$engineData;ProfilePath=$profile;ArchiveHashes=$archiveHashes;SettingsMode='Defaults'}
  # F013--F016 inspect every owned archive name before applying mod-list.json.
  # Preserve single-version external libraries. Coexisting owned versions
  # use the existing checkout-local selector and identity/hash restoration.
  if($historical -and ($historicalFixture.target -in @('f013','f014','f015','f016'))){
    $otherMirVersions=@($inventory | Where-Object {$_.name -ceq 'more-infinite-research' -and $_.version -cne $mirRows[0].version})
    if($historicalTransition -or $otherMirVersions.Count -gt 0){
      $activationArguments.PrePinMIROwnedArchiveNames=@('more-infinite-research')
    }
  }
  $activation=Start-MIRLibraryActivation @activationArguments
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $activation
  if($null -ne $activeModsObserverBinding){
    $actualObserver=@($activation.selected | Where-Object {[string]$_.name -ceq $activeModsObserverBinding.name})
    Assert-Fixture ($actualObserver.Count -eq 1) 'ActiveModsObserver must be selected exactly once in the activation'
    $actualObserver=$actualObserver[0]
    Assert-Fixture ([string]$actualObserver.version -ceq [string]$activeModsObserverBinding.version) 'ActiveModsObserver activation version differs from verified FixtureSources input'
    Assert-Fixture ((Get-FixtureSha ([string]$actualObserver.path)) -ceq [string]$activeModsObserverBinding.sha256) 'ActiveModsObserver activation archive differs from verified FixtureSources input'
    $record.active_mods_observer=[ordered]@{name=[string]$actualObserver.name;version=[string]$actualObserver.version;source=[string]$activeModsObserverBinding.source;archive=[string]$actualObserver.path;sha256=Get-FixtureSha ([string]$actualObserver.path)}
  }
  $activeSave=if($activeSeed){Join-Path $writeData 'saves/mir5-native-active.zip'}else{$null}
  $seed=$inputSave
  if(-not $seed){
    # `game.server_save` does not write from Factorio's single-player
    # --create context.  Repair's active preparation therefore earns its
    # sole closed pending save directly at the active-save destination.
    # Agriculture still creates seed.zip and has its existing server stage.
    $seed=if($activeSeed -and $ActiveSeedKind -ceq 'repair-stress'){$activeSave}else{Join-Path $writeData 'saves/seed.zip'}
    $createArguments=@(Get-FixtureCreateArguments -Seed $seed -Case $CaseName -OnlyCreate ([bool]$CreateOnly))
    $record.create=Invoke-FixtureStage 'create' $createArguments
    $record.create.consumers=Read-ConsumerResults ([IO.File]::ReadAllText($record.create.log)) 'init'
    Assert-Fixture (Test-Path -LiteralPath $seed -PathType Leaf) 'seed save absent'
  }
  $record.seed_sha256=Get-FixtureSha $seed
  $live=Join-Path $writeData 'factorio-current.log'
  if($activeSeed){
    if($ActiveSeedKind -ceq 'repair-stress'){
      Assert-Fixture ($seed -ceq $activeSave) 'active repair create save target differs'
      $record.active_preparation=@{stage='create';marker=(Read-ActiveFixtureMarker ([IO.File]::ReadAllText($record.create.log)) 'repair-stress' 'prepared')}
    }else{
      $server=Join-Path $resources.root 'server-settings.json'
      $record.server_settings=New-ModernFixtureServerSettings $server $engineData
      $activeSaveComplete=${function:Test-HistoricalFixtureSaveComplete}
      $activeCompletion={
        if(-not(Test-Path -LiteralPath $live -PathType Leaf)){return $false}
        $stream=[IO.File]::Open($live,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        $reader=[IO.StreamReader]::new($stream)
        try{$text=$reader.ReadToEnd()}finally{$reader.Dispose();$stream.Dispose()}
        if([regex]::IsMatch($text,'(?im)^\s*\d+[.]\d+\s+Error\b|^Error while running event\b|\bException at tick\b|\bnon-recoverable error\b|^stack traceback:$')){throw 'fatal native active preparation diagnostic'}
        if(-not(Test-Path -LiteralPath $activeSave -PathType Leaf)){return $false}
        try {
          $markers=@([regex]::Matches($text,'\[MIR5_RUNTIME_ACTIVE\] (\{[^\r\n]+\})') | ForEach-Object {$_.Groups[1].Value | ConvertFrom-Json} | Where-Object {
            [string]$_.kind -ceq 'agriculture-scale' -and [string]$_.stage -ceq 'prepared'
          })
        } catch {return $false}
        if($markers.Count -ne 1 -or [string]$markers[0].status -cne 'pending'){return $false}
        return $text.Contains('Saving finished') -and (& $activeSaveComplete $activeSave)
      }.GetNewClosure()
      $record.active_preparation=Invoke-FixtureStage 'active-prepare' @('--server-settings',$server,'--bind','127.0.0.1','--start-server',$seed) $activeCompletion
      $record.active_preparation.marker=Read-ActiveFixtureMarker ([IO.File]::ReadAllText($record.active_preparation.log)) 'agriculture-scale' 'prepared'
    }
    Assert-Fixture ((Test-Path -LiteralPath $activeSave -PathType Leaf) -and (Test-HistoricalFixtureSaveComplete $activeSave)) 'active fixture save is absent or not closed'
    $record.active_seed=[ordered]@{path=$activeSave;sha256=Get-FixtureSha $activeSave;marker_stage='prepared';kind=$ActiveSeedKind;physical_work='deferred until the benchmark loads this exact active save';preparation_outside_timed_benchmark=$true}
    $record.status='passed-private-native-active-seed-preparation'
  }elseif(-not $CreateOnly){
  $complete=Join-Path $writeData 'saves/mir5-native-complete.zip'
  $historicalSaveComplete=${function:Test-HistoricalFixtureSaveComplete}
  $completion={
    if(-not(Test-Path -LiteralPath $live -PathType Leaf)){return $false}
    $stream=[IO.File]::Open($live,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $reader=[IO.StreamReader]::new($stream)
    try{$text=$reader.ReadToEnd()}finally{$reader.Dispose();$stream.Dispose()}
    if([regex]::IsMatch($text,'(?im)^\s*\d+[.]\d+\s+Error\b|^Error while running event\b|\bException at tick\b|\bnon-recoverable error\b|^stack traceback:$')){throw 'fatal native production diagnostic'}
    if(-not $text.Contains('[MIR5_NATIVE_FIXTURE] RESULT ')){return $false}
    if(($f110PublishedCrossSource -or $f110SameEditionSuccessor) -and -not $text.Contains('[MIR5_NATIVE_FIXTURE] RESULT {"case":"f110-f200-transition","stage":"initial"')){return $false}
    if($laserTransition -and -not $text.Contains('[MIR5_NATIVE_FIXTURE] RESULT {"case":"f100-f110-laser-transition","stage":"initial","role":"'+$F100F110LaserStage+'"')){return $false}
    if($publishedF100Forward -and -not $text.Contains('[MIR5_NATIVE_FIXTURE] RESULT {"case":"published-f100-forward","stage":"initial","role":"'+$publishedF100Fixture.role+'","target":"'+$publishedF100Fixture.target+'"')){return $false}
    if($historicalProcess){return & $historicalSaveComplete $complete}
    return (Test-Path -LiteralPath $complete -PathType Leaf) -and $text.Contains('Saving finished')
  }.GetNewClosure()
  if($historicalProcess){
    $serverSettings=New-HistoricalFixtureServerSettings (Join-Path $resources.root 'server-settings.json') $engineData $historicalProcessVersion
    $record.historical_server_settings=$serverSettings
    $historicalServerArguments=@($serverSettings.arguments)
    $record.production=Invoke-FixtureStage 'production' ($historicalServerArguments+@('--start-server',$seed)) $completion
    $record.historical_server_mode='start-server-two-cold-reloads'
  }else{
    $server=Join-Path $resources.root 'server-settings.json'
    $record.server_settings=New-ModernFixtureServerSettings $server $engineData
    $record.production=Invoke-FixtureStage 'production' @('--server-settings',$server,'--bind','127.0.0.1','--start-server',$seed) $completion
  }
  $record.production.consumers=Read-ConsumerResults ([IO.File]::ReadAllText($record.production.log)) $ProductionConsumerStage
  $record.initial=Read-FixtureResult ([IO.File]::ReadAllText($record.production.log)) 'initial'
  if($laserTransition){Assert-Fixture ([string]$record.initial.role -ceq $F100F110LaserStage) 'laser initial role differs'}
  if($historicalTransition){Assert-Fixture ([string]$record.initial.transition_stage -ceq $HistoricalTransitionStage) 'historical transition predecessor or successor witness differs'}
  $saveHash=Get-FixtureSha $complete
  $record.reloads=@()
  foreach($ordinal in 1..2){
    $reloadArguments=if($historicalProcess){$historicalServerArguments+@('--start-server',$complete)}else{@('--benchmark',$complete,'--benchmark-ticks','1','--benchmark-runs','1','--benchmark-sanitize')}
    $reloadCompletion=$null
    if($historicalProcess){
      $reloadCompletion={
        if(-not(Test-Path -LiteralPath $live -PathType Leaf)){return $false}
        $stream=[IO.File]::Open($live,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        $reader=[IO.StreamReader]::new($stream)
        try{$text=$reader.ReadToEnd()}finally{$reader.Dispose();$stream.Dispose()}
        if([regex]::IsMatch($text,'(?im)^\s*\d+[.]\d+\s+Error\b|^Error while running event\b|\bException at tick\b|\bnon-recoverable error\b|^stack traceback:$')){throw 'fatal native historical reload diagnostic'}
        $reloadCase=if($f110PublishedCrossSource -or $f110SameEditionSuccessor){'f110-f200-transition'}elseif($laserTransition){'f100-f110-laser-transition'}elseif($historicalTransition){'historical-transition'}else{'historical-native'}
        $reloadTransition=if($historicalTransition){',"transition_stage":"'+$HistoricalTransitionStage+'"'}else{''}
        $reloadForward=''
        if($publishedF100Forward){$reloadCase='published-f100-forward';$reloadForward=',"role":"'+$publishedF100Fixture.role+'","target":"'+$publishedF100Fixture.target+'"'}
        return $text.Contains('[MIR5_NATIVE_FIXTURE] RESULT {"case":"'+$reloadCase+'","stage":"reload"'+$reloadTransition+$reloadForward)
      }.GetNewClosure()
    }
    $stage=Invoke-FixtureStage ('reload-'+$ordinal) $reloadArguments $reloadCompletion
    $result=Read-FixtureResult ([IO.File]::ReadAllText($stage.log)) 'reload'
    if($laserTransition){Assert-Fixture ([string]$result.role -ceq $F100F110LaserStage) 'laser reload role differs'}
    if($historicalTransition){Assert-Fixture ([string]$result.transition_stage -ceq $HistoricalTransitionStage) 'historical transition reload witness differs'}
    $stage.consumers=Read-ConsumerResults ([IO.File]::ReadAllText($stage.log)) 'load'
    Assert-Fixture ((Get-FixtureSha $complete) -ceq $saveHash) 'cold reload changed completed save bytes'
    $record.reloads+=@{ordinal=$ordinal;stage=$stage;result=$result;save_sha256=$saveHash;save_byte_identical=$true}
  }
  $record.status='passed-private-native-fixture'
  }else{
    $record.status='passed-private-native-runtime-load-only'
  }
}catch{
  $record.status='failed';$record.failure=$_.Exception.Message;$record.resource_admission=$_.Exception.Data['mir441_resource_admission'];$failure=$_
}finally{
  try{
    if($null -ne $activation -and -not $activation.closed){$record.library_control_restoration=Complete-MIRLibraryActivation -Activation $activation}
    if($inputSave){
      $record.input_save_byte_identical=(Get-FixtureSha $inputSave) -ceq $ExpectedInputSaveSha256.ToUpperInvariant()
      Assert-Fixture $record.input_save_byte_identical 'native fixture changed the supplied historical save'
    }
  }catch{
    $record.library_control_restoration_failure=$_.Exception.Message
    if($null -eq $failure){$record.status='failed';$record.failure=$_.Exception.Message;$failure=$_}
  }finally{
    if($null -ne $resources){
      $record.process_runs=@($resources.runs.ToArray())
      Write-MIRNativeProbeResult -Context $resources -Record $record
    }
  }
}
if($null -ne $failure){throw $failure}
[pscustomobject]$record
