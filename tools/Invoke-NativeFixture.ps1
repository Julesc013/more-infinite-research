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
  [switch]$CreateOnly,
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
function Assert-FixtureLog([string]$Text) {
  Assert-Fixture (-not [regex]::IsMatch($Text,'(?im)^\s*\d+[.]\d+\s+Error\b|^Error while running event\b|\bException at tick\b|\bnon-recoverable error\b|^stack traceback:$')) 'fatal native diagnostic'
}
function Read-FixtureResult([string]$Text,[string]$Stage) {
  $rows=@([regex]::Matches($Text,'\[MIR5_NATIVE_FIXTURE\] RESULT (\{[^\r\n]+\})') | ForEach-Object {$_.Groups[1].Value | ConvertFrom-Json} | Where-Object {$_.case -ceq $CaseName -and $_.stage -ceq $Stage})
  Assert-Fixture ($rows.Count -eq 1 -and $rows[0].status -ceq 'passed') "missing unique passed $Stage witness for $CaseName"
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
function Get-HistoricalFixtureTarget([string]$Target,[string]$MetadataPath) {
  $allowed=@('f013','f014','f015','f016','f017','f100','f110')
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
  Assert-Fixture ($Target -cmatch '^f(?:013|014|015|016|017|100|110)$') 'historical target literal identity differs'
  foreach($field in @('direct','continuation')){
    Assert-Fixture ([string]$selected[$field] -cmatch '^[a-z0-9][a-z0-9_-]*$') "historical target $field is not a literal-safe identifier"
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
  [pscustomobject][ordered]@{path=$metadata;sha256=Get-FixtureSha $metadata;name=[string]$value.name;version=[string]$value.version;target=$Target;factorio_version=[string]$selected.factorio_version;minimum_base=[string]$selected.minimum_base;mir_version=[string]$selected.mir_version;definition=$selected}
}
function ConvertTo-HistoricalFixtureTargetLiteral($Fixture) {
  $value=$Fixture.definition
  $lines=[Collections.Generic.List[string]]::new()
  $lines.Add('return {')
  $lines.Add(('  id="{0}",' -f $Fixture.target))
  foreach($field in @('mir_version','direct','continuation','continuation_mode')){
    $lines.Add(('  {0}="{1}",' -f $field,[string]$value[$field]))
  }
  $effect=[double]$value.direct_effect
  $lines.Add(('  direct_effect={0},' -f $effect.ToString('0.################',[Globalization.CultureInfo]::InvariantCulture)))
  if($value.ContainsKey('queue_api') -and [bool]$value.queue_api){$lines.Add('  queue_api=true,')}
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
    Assert-Fixture ((@($info.dependencies) -join "`n") -ceq ($expectedInfo.dependencies -join "`n")) 'historical fixture dependencies differ'
  } finally {$zip.Dispose()}
}
function Get-HistoricalTransitionFixtureTarget([string]$Target,[string]$MetadataPath,[string]$Stage) {
  $allowed=@('f013','f014','f015','f016','f017','f100','f110')
  Assert-Fixture ($Target -in $allowed) 'historical transition target is unsupported'
  Assert-Fixture ($Stage -in @('published','mir5')) 'historical transition stage is unsupported'
  $metadata=(Resolve-Path -LiteralPath $MetadataPath).Path
  $value=Get-Content -LiteralPath $metadata -Raw|ConvertFrom-Json -AsHashtable
  Assert-Fixture ($value.kind -ceq 'MIR5HistoricalTransitionFixtureV1' -and $value.schema -eq 1) 'historical transition fixture metadata differs'
  Assert-Fixture ([string]$value.name -ceq 'mir-fixture-mir5-historical-transition' -and [string]$value.version -ceq '0.1.0') 'historical transition fixture identity differs'
  $selected=$value.targets[$Target]
  Assert-Fixture ($null -ne $selected) 'historical transition fixture lacks selected target'
  foreach($field in @('factorio_version','minimum_base','published_mir_version','mir_version','published_archive_sha256','direct','direct_effect','successor_mode')){
    Assert-Fixture ($selected.ContainsKey($field) -and -not [string]::IsNullOrWhiteSpace([string]$selected[$field])) "historical transition target lacks $field"
  }
  Assert-Fixture ($Target -cmatch '^f(?:013|014|015|016|017|100|110)$') 'historical transition target literal identity differs'
  Assert-Fixture ([string]$selected.factorio_version -cmatch '^(?:0[.]1[3-7]|1[.][01])$') 'historical transition factorio version differs'
  $edition=$Target.Substring(1)
  Assert-Fixture ([string]$selected.published_mir_version -ceq ('4.7.'+$edition+'02') -and [string]$selected.mir_version -ceq ('5.0.'+$edition+'00')) 'historical transition MIR versions differ'
  Assert-Fixture ([string]$selected.published_archive_sha256 -cmatch '^[A-Fa-f0-9]{64}$') 'historical transition published archive hash differs'
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
    Assert-Fixture ((@($info.dependencies) -join "`n") -ceq ($expectedInfo.dependencies -join "`n")) 'historical transition fixture dependencies differ'
  } finally {$zip.Dispose()}
}
function New-HistoricalFixtureServerSettings([string]$Path,[string]$EngineData,[string]$FactorioVersion) {
  Assert-Fixture ($FactorioVersion -in @('0.13','0.14','0.15','0.16','0.17','1.0','1.1')) 'historical server target differs'
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
function Invoke-FixtureStage([string]$Name,[string[]]$StageArguments,[scriptblock]$Completion=$null) {
  $live=Join-Path $writeData 'factorio-current.log'
  if(Test-Path -LiteralPath $live){Remove-Item -LiteralPath $live}
  $arguments=@('--config',$config,'--mod-directory',$activation.library,'--no-log-rotation')
  if(-not $historical -or $historicalFixture.factorio_version -notin @('0.13','0.14')){$arguments+='--disable-audio'}
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
$historicalFixture=$null
if($historicalTransition){
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
  $base=Get-Content -LiteralPath (Join-Path $engineData 'base/info.json') -Raw|ConvertFrom-Json -AsHashtable
  Assert-Fixture ([string]$base.version -ceq $historicalFixture.minimum_base) 'historical transition engine base differs from target metadata'
}elseif($historical){
  Assert-Fixture (-not $CreateOnly -and -not $MIRAbsent -and -not $InputSavePath -and -not $ExpectedInputSaveSha256) 'historical fixtures require a fresh full run'
  Assert-Fixture ($CaseName -ceq 'historical-native' -and $ConsumerMarkers.Count -eq 0) 'historical fixtures use their own marker without modern consumers'
  Assert-Fixture ([string]::IsNullOrWhiteSpace($activeModsObserverName)) 'historical fixtures do not select a modern active-mod observer'
  Assert-Fixture ([string]::IsNullOrWhiteSpace($HistoricalTransitionFixtureMetadataPath)) 'fresh historical fixture must not use transition metadata'
  Assert-Fixture ($FixtureSources.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($HistoricalFixtureMetadataPath)) 'historical fixtures require one source and its metadata'
  $historicalFixture=Get-HistoricalFixtureTarget -Target $HistoricalTarget -MetadataPath $HistoricalFixtureMetadataPath
  $base=Get-Content -LiteralPath (Join-Path $engineData 'base/info.json') -Raw|ConvertFrom-Json -AsHashtable
  Assert-Fixture ([string]$base.version -ceq $historicalFixture.minimum_base) 'historical fixture engine base differs from target metadata'
}else{
  Assert-Fixture ([string]::IsNullOrWhiteSpace($HistoricalFixtureMetadataPath) -and [string]::IsNullOrWhiteSpace($HistoricalTransitionFixtureMetadataPath)) 'modern fixture runs do not accept historical metadata'
}
$inputSave=$null
if($InputSavePath -or $ExpectedInputSaveSha256){
  Assert-Fixture (-not $CreateOnly -and -not $MIRAbsent -and $InputSavePath -and $ExpectedInputSaveSha256 -cmatch '^[a-fA-F0-9]{64}$') 'an input save requires a full fixture run and exact hash'
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
$rows=@((Get-Content -LiteralPath $profile -Raw | ConvertFrom-Json -AsHashtable).mods)
$inventory=@(Get-MIRLibraryInventory -LibraryDirectory $library -EngineDataDirectory $engineData)
$mirRows=@($rows | Where-Object {$_.name -ceq 'more-infinite-research' -and $_.enabled})
$mir=@()
if($MIRAbsent){
  Assert-Fixture ($CreateOnly -and $mirRows.Count -eq 0 -and $ExpectedMIRArchiveSha256 -ceq '') 'MIR absence requires a create-only profile without MIR or its hash'
}else{
  Assert-Fixture ($mirRows.Count -eq 1 -and $ExpectedMIRArchiveSha256 -match '^[a-fA-F0-9]{64}$') 'one pinned MIR selection is required'
  $mir=@($inventory | Where-Object {$_.name -ceq 'more-infinite-research' -and $_.version -ceq $mirRows[0].version})
  Assert-Fixture ($mir.Count -eq 1 -and (Get-FixtureSha $mir[0].path) -ceq $ExpectedMIRArchiveSha256.ToUpperInvariant()) 'MIR archive hash differs'
  if($historicalTransition){
    Assert-Fixture ([string]$mirRows[0].version -ceq [string]$historicalFixture.mir_version) 'historical transition profile MIR version differs'
    if($HistoricalTransitionStage -ceq 'published'){
      Assert-Fixture ($ExpectedMIRArchiveSha256.ToUpperInvariant() -ceq [string]$historicalFixture.definition.published_archive_sha256) 'historical transition published archive hash differs'
    }
  }
}
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
$activeModsObserverBinding=Get-FixtureActiveModsObserver -Name $activeModsObserverName -ProfileRows $rows -FixtureInputs $fixtureBindings
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 2 -MaxEntriesPerRoot 500 | Out-Host
$resources=$null;$activation=$null;$failure=$null
$record=[ordered]@{
  kind='MIR5NativeFixtureV1';status='prepared';case=$CaseName
  source_head=[string](& git -C $repo rev-parse HEAD)
  source_dirty=(@(& git -C $repo status --porcelain=v1).Count -gt 0)
  harness_sha256=Get-FixtureSha $PSCommandPath
  native_probe_sha256=Get-FixtureSha (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
  governor_sha256=Get-FixtureSha (Join-Path $repo 'tools/lib/validation/ResourceGovernor.ps1')
  engine=Get-MIRDirectLibraryStartupEngineIdentity -FactorioBin $engine -EngineDataDirectory $engineData
  profile=@{path=$profile;sha256=Get-FixtureSha $profile};fixtures=$fixtureInputs
  historical_target=if($historical){@{id=$historicalFixture.target;metadata_path=$historicalFixture.path;metadata_sha256=$historicalFixture.sha256;factorio_version=$historicalFixture.factorio_version;minimum_base=$historicalFixture.minimum_base;mir_version=$historicalFixture.mir_version}}else{$null}
  historical_transition=if($historicalTransition){@{stage=$HistoricalTransitionStage;published_archive_sha256=[string]$historicalFixture.definition.published_archive_sha256;predecessor_mir_version=[string]$historicalFixture.definition.published_mir_version;successor_mir_version=[string]$historicalFixture.definition.mir_version}}else{$null}
  mir_archive=if($MIRAbsent){$null}else{@{path=$mir[0].path;sha256=$ExpectedMIRArchiveSha256.ToUpperInvariant()}}
  observation=if($CreateOnly){'native-create-runtime-load-only'}else{'native-fixture-production-and-two-cold-reloads'}
  input_save=if($inputSave){@{path=$inputSave;sha256=$ExpectedInputSaveSha256.ToUpperInvariant()}}else{$null}
  release_qualification=$false
}
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
  if($historical){
    # Older engines use the retained direct-library minimal form.  Do not
    # inherit modern option keys into F013--F110.
    $historicalConfig=@('[path]',"read-data=$($engineData.Replace('\','/'))","write-data=$($writeData.Replace('\','/'))",'', '[other]','check-updates=false','enable-new-mods=false') -join "`n"
    [IO.File]::WriteAllText($config,$historicalConfig+"`n",[Text.UTF8Encoding]::new($false))
  }else{
    New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $engineData -WriteDataDirectory $writeData
  }
  $hashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $library -EngineDataDirectory $engineData -BaseRows $rows -MirArchive $null
  $activationArguments=@{LibraryDirectory=$library;EngineDataDirectory=$engineData;ProfilePath=$profile;ArchiveHashes=$hashes;SettingsMode='Defaults'}
  # F013--F016 inspect every owned archive name before applying mod-list.json.
  # Pin the selected MIR version in the existing durable activation transaction
  # for both fresh historical fixtures and predecessor-to-successor transitions.
  if($historical -and ($historicalFixture.target -in @('f013','f014','f015','f016'))){
    $activationArguments.PrePinMIROwnedArchiveNames=@('more-infinite-research')
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
  $seed=$inputSave
  if(-not $seed){
    $seed=Join-Path $writeData 'saves/seed.zip'
    $record.create=Invoke-FixtureStage 'create' @('--create',$seed)
    $record.create.consumers=Read-ConsumerResults ([IO.File]::ReadAllText($record.create.log)) 'init'
    Assert-Fixture (Test-Path -LiteralPath $seed -PathType Leaf) 'seed save absent'
  }
  $record.seed_sha256=Get-FixtureSha $seed
  if(-not $CreateOnly){
  $complete=Join-Path $writeData 'saves/mir5-native-complete.zip'
  $live=Join-Path $writeData 'factorio-current.log'
  $historicalSaveComplete=${function:Test-HistoricalFixtureSaveComplete}
  $completion={
    if(-not(Test-Path -LiteralPath $live -PathType Leaf)){return $false}
    $stream=[IO.File]::Open($live,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $reader=[IO.StreamReader]::new($stream)
    try{$text=$reader.ReadToEnd()}finally{$reader.Dispose();$stream.Dispose()}
    if([regex]::IsMatch($text,'(?im)^\s*\d+[.]\d+\s+Error\b|^Error while running event\b|\bException at tick\b|\bnon-recoverable error\b|^stack traceback:$')){throw 'fatal native production diagnostic'}
    if(-not $text.Contains('[MIR5_NATIVE_FIXTURE] RESULT ')){return $false}
    if($historical){return & $historicalSaveComplete $complete}
    return (Test-Path -LiteralPath $complete -PathType Leaf) -and $text.Contains('Saving finished')
  }.GetNewClosure()
  if($historical){
    $serverSettings=New-HistoricalFixtureServerSettings (Join-Path $resources.root 'server-settings.json') $engineData $historicalFixture.factorio_version
    $record.historical_server_settings=$serverSettings
    $historicalServerArguments=@($serverSettings.arguments)
    $record.production=Invoke-FixtureStage 'production' ($historicalServerArguments+@('--start-server',$seed)) $completion
    $record.historical_server_mode='start-server-two-cold-reloads'
  }else{
    $server=Join-Path $resources.root 'server-settings.json'
    $serverTemplate=Join-Path $engineData 'server-settings.example.json'
    $serverSettings=Get-Content -LiteralPath $serverTemplate -Raw | ConvertFrom-Json -AsHashtable
    $serverSettings.name='MIR private native fixture'
    $serverSettings.description=''
    $serverSettings.visibility=@{public=$false;lan=$false}
    $serverSettings.username='';$serverSettings.password='';$serverSettings.token='';$serverSettings.game_password=''
    $serverSettings.require_user_verification=$false
    $serverSettings.auto_pause=$false
    $serverSettings.autosave_interval=0
    $serverSettings.max_players=1
    [IO.File]::WriteAllText($server,($serverSettings | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    $record.server_settings=@{template=$serverTemplate;template_sha256=Get-FixtureSha $serverTemplate;path=$server;sha256=Get-FixtureSha $server}
    $record.production=Invoke-FixtureStage 'production' @('--server-settings',$server,'--bind','127.0.0.1','--start-server',$seed) $completion
  }
  $record.production.consumers=Read-ConsumerResults ([IO.File]::ReadAllText($record.production.log)) $ProductionConsumerStage
  $record.initial=Read-FixtureResult ([IO.File]::ReadAllText($record.production.log)) 'initial'
  if($historicalTransition){Assert-Fixture ([string]$record.initial.transition_stage -ceq $HistoricalTransitionStage) 'historical transition predecessor or successor witness differs'}
  $saveHash=Get-FixtureSha $complete
  $record.reloads=@()
  foreach($ordinal in 1..2){
    $reloadArguments=if($historical){$historicalServerArguments+@('--start-server',$complete)}else{@('--benchmark',$complete,'--benchmark-ticks','1','--benchmark-runs','1','--benchmark-sanitize')}
    $reloadCompletion=$null
    if($historical){
      $reloadCompletion={
        if(-not(Test-Path -LiteralPath $live -PathType Leaf)){return $false}
        $stream=[IO.File]::Open($live,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        $reader=[IO.StreamReader]::new($stream)
        try{$text=$reader.ReadToEnd()}finally{$reader.Dispose();$stream.Dispose()}
        if([regex]::IsMatch($text,'(?im)^\s*\d+[.]\d+\s+Error\b|^Error while running event\b|\bException at tick\b|\bnon-recoverable error\b|^stack traceback:$')){throw 'fatal native historical reload diagnostic'}
        $reloadCase=if($historicalTransition){'historical-transition'}else{'historical-native'}
        $reloadTransition=if($historicalTransition){',"transition_stage":"'+$HistoricalTransitionStage+'"'}else{''}
        return $text.Contains('[MIR5_NATIVE_FIXTURE] RESULT {"case":"'+$reloadCase+'","stage":"reload"'+$reloadTransition)
      }.GetNewClosure()
    }
    $stage=Invoke-FixtureStage ('reload-'+$ordinal) $reloadArguments $reloadCompletion
    $result=Read-FixtureResult ([IO.File]::ReadAllText($stage.log)) 'reload'
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
