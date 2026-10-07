# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [Parameter(Mandatory)][string]$CandidateManifestPath,
  [Parameter(Mandatory)][string]$F210Engine,
  [Parameter(Mandatory)][string]$F200Engine,
  [Parameter(Mandatory)][string]$F110Engine,
  [Parameter(Mandatory)][string]$F100Engine,
  [Parameter(Mandatory)][string]$F210Predecessor,
  [Parameter(Mandatory)][string]$F200Predecessor,
  [Parameter(Mandatory)][string]$F110Predecessor,
  [Parameter(Mandatory)][string]$F100Predecessor,
  [Parameter(Mandatory)][string]$OutputRoot,
  [string]$LibraryBindingsPath = '',
  [string]$PublishedMaintenancePredecessorManifestPath = '',
  [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB = 0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB = 512,
  [ValidateRange(60,900)][int]$RowDeadlineSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/NativeProbeResources.ps1')
. (Join-Path $RepoRoot 'tools/lib/compatibility/FactorioRunner.ps1')

$script:MIR42ModernEngineTargets = @('f210','f200','f110','f100')
$script:MIR42HistoricalEngineTargets = @('f017','f016','f015','f014','f013')
$script:MIR42NineTargetEngineTargets = @($script:MIR42ModernEngineTargets + $script:MIR42HistoricalEngineTargets)
$script:MIR42HistoricalTerminalInputs = [ordered]@{
  f017 = [ordered]@{ line='0.17'; predecessor='1.7.9'; target_record='targets/historical/f017/target.json'; terminal_seal='.mir/releases/terminal/seals/1.7.9.json' }
  f016 = [ordered]@{ line='0.16'; predecessor='1.6.9'; target_record='targets/historical/f016/target.json'; terminal_seal='.mir/releases/terminal/seals/1.6.9.json' }
  f015 = [ordered]@{ line='0.15'; predecessor='1.5.9'; target_record='targets/historical/f015/target.json'; terminal_seal='.mir/releases/terminal/seals/1.5.9.json' }
  f014 = [ordered]@{ line='0.14'; predecessor='1.4.9'; target_record='targets/historical/f014/target.json'; terminal_seal='.mir/releases/terminal/seals/1.4.9.json' }
  f013 = [ordered]@{ line='0.13'; predecessor='1.3.9'; target_record='targets/historical/f013/target.json'; terminal_seal='.mir/releases/terminal/seals/1.3.9.json' }
}

function Assert-MIR42EngineRunFile {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Label)
  $resolved = [IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "[$Label-missing] $resolved" }
  return $resolved
}

function Get-MIR42EngineRunSha {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-MIR42EngineRunArchiveVersion {
  param([Parameter(Mandatory)][string]$Path)
  $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entries = @($archive.Entries | Where-Object { $_.FullName -match '^[^/]+/info[.]json$' })
    if ($entries.Count -ne 1) { throw '[mir42-engine-archive-info-entry]' }
    $reader = [IO.StreamReader]::new($entries[0].Open())
    try { $info = $reader.ReadToEnd() | ConvertFrom-Json -Depth 20 -DateKind String }
    finally { $reader.Dispose() }
    return [string]$info.version
  } finally { $archive.Dispose() }
}

function Get-MIR42EngineCandidateVersionContract {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$ManifestPath)
  $path = Assert-MIR42EngineRunFile -Path $ManifestPath -Label 'mir42-candidate-manifest'
  $raw = Get-Content -Raw -LiteralPath $path
  $manifest = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  $version = Get-MIR42CandidateConstructionVersionContract -RepoRoot $RepoRoot -Manifest $manifest
  if (-not (Test-Path -LiteralPath $version.schema_path -PathType Leaf) -or
      -not ($raw | Test-Json -SchemaFile $version.schema_path -ErrorAction SilentlyContinue)) {
    throw '[mir42-engine-candidate-manifest-schema]'
  }
  $targets = @($manifest.targets | ForEach-Object { [string]$_.target })
  $nine = (($targets -join '|') -ceq ($script:MIR42NineTargetEngineTargets -join '|'))
  $four = (($targets -join '|') -ceq ($script:MIR42ModernEngineTargets -join '|'))
  $status = if ($nine) { 'private-deterministic-nine-target-candidate-built-unqualified' }
    elseif ($four) { 'private-deterministic-four-target-candidate-built-unqualified' } else { '' }
  if ([string]::IsNullOrWhiteSpace($status) -or [string]$manifest.status -cne $status -or
      ([bool]$version.requires_nine_targets -and -not $nine) -or
      -not [bool]$manifest.build_complete -or -not (Test-MIR4BootstrapRecordHash -Record $manifest)) {
    throw '[mir42-engine-candidate-manifest-invalid]'
  }
  # This validates the versioned envelope only. The caller still authenticates
  # the clean source snapshot, package authority, every archive and engine,
  # published predecessor custody and resource admission before execution.
  return [pscustomobject][ordered]@{
    path=$path;manifest=$manifest;source_version=[string]$version.source_version
    nine_targets=$nine;four_targets=$four;targets=$targets
  }
}

function Get-MIR42HistoricalEngineDescriptor {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('f017','f016','f015','f014','f013')][string]$Target,
    [ValidateSet('4.2.0','4.2.1')][string]$SourceVersion = '4.2.0'
  )
  $expected = $script:MIR42HistoricalTerminalInputs[$Target]
  $recordPath = Assert-MIR42EngineRunFile -Path (Join-Path $RepoRoot ([string]$expected.target_record)) -Label "mir42-$Target-target-record"
  try { $record = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json -Depth 100 -DateKind String }
  catch { throw "[mir42-$Target-target-record-json]" }
  if (-not (Test-MIR4BootstrapRecordHash -Record $record) -or
      [int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42HistoricalPlaytestTargetV1' -or
      [string]$record.target -cne $Target -or [string]$record.maturity -cne 'private-historical-playtest' -or
      [string]$record.base_materializer_target -cne 'f100' -or [string]$record.factorio_line -cne [string]$expected.line -or
      [string]$record.distribution_version -cne ('4.2.' + $Target.Substring(1) + '00') -or
      [bool]$record.public_output_authorized -or [bool]$record.publication_authorized) {
    throw "[mir42-$Target-target-record-state]"
  }
  $sealPath = Assert-MIR42EngineRunFile -Path (Join-Path $RepoRoot ([string]$expected.terminal_seal)) -Label "mir42-$Target-terminal-seal"
  try { $seal = Get-Content -Raw -LiteralPath $sealPath | ConvertFrom-Json -Depth 100 -DateKind String }
  catch { throw "[mir42-$Target-terminal-seal-json]" }
  if (-not (Test-MIR4BootstrapRecordHash -Record $seal) -or
      [int]$seal.schema -ne 1 -or [string]$seal.kind -cne 'Mir3TerminalTargetSealV1' -or [string]$seal.status -cne 'sealed' -or
      [string]$seal.release -cne [string]$expected.predecessor -or [string]$seal.target -cne [string]$expected.line -or
      [string]$seal.archive_sha256 -cne [string]$record.predecessor.sha256 -or
      [string]$seal.engine.version -cne [string]$record.engine.version -or [string]$seal.engine.binary_sha256 -cne [string]$record.engine.sha256) {
    throw "[mir42-$Target-terminal-seal-binding]"
  }
  $predecessorRelative = [string]$record.predecessor.archive
  if ([IO.Path]::IsPathRooted($predecessorRelative) -or $predecessorRelative -match '(^|[\\/])[.][.]([\\/]|$)' -or
      $predecessorRelative.Replace('\\','/') -cne ('dist/more-infinite-research_' + [string]$expected.predecessor + '.zip') -or
      [string]$record.predecessor.version -cne [string]$expected.predecessor) {
    throw "[mir42-$Target-predecessor-path]"
  }
  $expectedEngine = [IO.Path]::GetFullPath((Join-Path ('D:\Programs\Factorio\' + [string]$expected.line) 'bin/x64/factorio.exe'))
  $recordEngine = [IO.Path]::GetFullPath([string]$record.engine.path)
  if (-not $recordEngine.Equals($expectedEngine,[StringComparison]::OrdinalIgnoreCase) -or
      [string]$record.engine.version -notmatch '^0[.][0-9]+[.][0-9]+$' -or [string]$record.engine.sha256 -notmatch '^[A-F0-9]{64}$') {
    throw "[mir42-$Target-engine-authority]"
  }
  return [ordered]@{
    engine = $recordEngine
    predecessor = [IO.Path]::GetFullPath((Join-Path $RepoRoot $predecessorRelative))
    from = [string]$record.predecessor.version
    to = [string](Get-MIR42ReleaseTargetIdentity -RepoRoot $RepoRoot -Target $Target -SourceVersion $SourceVersion).distribution_version
    historical = [ordered]@{
      target_record = [ordered]@{path=[string]$expected.target_record;sha256=(Get-MIR42EngineRunSha -Path $recordPath);record_sha256=[string]$record.record_sha256}
      terminal_seal = [ordered]@{path=[string]$expected.terminal_seal;sha256=(Get-MIR42EngineRunSha -Path $sealPath);record_sha256=[string]$seal.record_sha256;target=[string]$seal.target;release=[string]$seal.release}
      engine = [ordered]@{path=$recordEngine;version=[string]$record.engine.version;sha256=[string]$record.engine.sha256}
      predecessor = [ordered]@{path=$predecessorRelative;version=[string]$record.predecessor.version;sha256=[string]$record.predecessor.sha256;bytes=[int64]$seal.bytes;content_sha256=[string]$seal.content_sha256;entry_count=[int]$seal.entries}
    }
  }
}

function Assert-MIR42HistoricalUpgradeHarness {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $fixture = Assert-MIR42EngineRunFile -Path (Join-Path $RepoRoot 'fixtures/assert-upgrade-historical-terminal-to-mir42/info.json') -Label 'mir42-historical-upgrade-fixture-info'
  $control = Assert-MIR42EngineRunFile -Path (Join-Path $RepoRoot 'fixtures/assert-upgrade-historical-terminal-to-mir42/control.lua') -Label 'mir42-historical-upgrade-fixture-control'
  $upgradeHarness = Assert-MIR42EngineRunFile -Path (Join-Path $RepoRoot 'tests/runtime/Test-MIRUpgrade.ps1') -Label 'mir42-historical-upgrade-harness'
  $info = Get-Content -Raw -LiteralPath $fixture
  $controlText = Get-Content -Raw -LiteralPath $control
  $upgradeHarnessText = Get-Content -Raw -LiteralPath $upgradeHarness
  $reloadLogClear = "[IO.File]::WriteAllText(`$log, '', [Text.UTF8Encoding]::new(`$false))"
  $firstReloadLogClear = $upgradeHarnessText.IndexOf($reloadLogClear,[StringComparison]::Ordinal)
  $firstReloadProcess = $upgradeHarnessText.IndexOf('$reloadExitCode = ',[StringComparison]::Ordinal)
  $secondReloadLogClear = $upgradeHarnessText.IndexOf($reloadLogClear,$firstReloadProcess,[StringComparison]::Ordinal)
  $secondReloadProcess = $upgradeHarnessText.IndexOf('$secondReloadExitCode = ',[StringComparison]::Ordinal)
  if (-not $info.Contains('@@FACTORIO_LINE@@') -or -not $info.Contains('@@MIR_UPGRADE_FROM_VERSION@@') -or
      -not $controlText.Contains('__MIR_UPGRADE_FROM_VERSION__') -or -not $controlText.Contains('__MIR_UPGRADE_TO_VERSION__') -or
      -not $controlText.Contains('script.on_configuration_changed') -or -not $controlText.Contains('script.on_load') -or
      -not $controlText.Contains('game.server_save') -or -not $controlText.Contains('research-speed-4') -or
      -not $controlText.Contains('force().research_queue = { research.name }') -or
      $controlText.Contains('game.active_mods') -or
      -not $upgradeHarnessText.Contains('$isHistoricalTerminalFixture = $FixtureName -eq ''assert-upgrade-historical-terminal-to-mir42''') -or
      -not $upgradeHarnessText.Contains('$isLegacyFactorio = $isHistoricalTerminalFixture -or') -or
      -not $upgradeHarnessText.Contains('MIR historical upgrade specialization requires an exact terminal predecessor') -or
      $firstReloadLogClear -lt 0 -or $firstReloadProcess -lt 0 -or $secondReloadLogClear -le $firstReloadProcess -or $secondReloadProcess -le $secondReloadLogClear) {
    throw '[mir42-historical-upgrade-harness-contract]'
  }
  return [ordered]@{fixture_path=$fixture;fixture_sha256=(Get-MIR42EngineRunSha -Path $fixture);control_path=$control;control_sha256=(Get-MIR42EngineRunSha -Path $control);upgrade_harness_path=$upgradeHarness;upgrade_harness_sha256=(Get-MIR42EngineRunSha -Path $upgradeHarness)}
}

function Invoke-MIR42BoundedUpgrade {
  param([Parameter(Mandatory)][string]$PowerShell,[Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$StdoutPath,[Parameter(Mandatory)][string]$StderrPath,
    [Parameter(Mandatory)][int]$DeadlineSeconds,[switch]$NativeActor)
  foreach($path in @($StdoutPath,$StderrPath)){
    $null=Assert-MIRImmutableInputPathWithin -Path $path -Root $resources.root -Context 'Engine row capture'
  }
  # Fresh-load actors have no inner governor. The existing upgrade harness
  # governs its own native actors, so its outer deadline must not take that lock.
  if($NativeActor){
    $actor=Invoke-MIRNativeProbeProcess -Context $resources -FilePath $PowerShell -Arguments $Arguments -TimeoutSeconds $DeadlineSeconds
    foreach($capture in @(@{source=$actor.stdout;destination=$StdoutPath},@{source=$actor.stderr;destination=$StderrPath})){
      if([IO.Path]::GetFullPath($capture.source) -cne [IO.Path]::GetFullPath($capture.destination)){
        Move-Item -LiteralPath $capture.source -Destination $capture.destination
      }
    }
    $actor.stdout=$StdoutPath;$actor.stderr=$StderrPath
    return [int]$actor.result.exit_code
  }
  # The upgrade worker owns its existing native governor and heavy-job lock.
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = $PowerShell
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  foreach ($argument in $Arguments) { [void]$start.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::Start($start)
  $clock = [Diagnostics.Stopwatch]::StartNew()
  try {
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($DeadlineSeconds * 1000)
    if ($timedOut) {
      try { $process.Kill($true) } catch { $process.Kill() }
    }
    if (-not $process.HasExited -and -not $process.WaitForExit(5000)) {
      throw '[mir42-engine-row-termination-failed]'
    }
    # A child can leave inherited output handles open after the harness exits.
    # The same deadline covers draining those handles; never await them forever.
    $remainingMs = [int][Math]::Max(0,($DeadlineSeconds * 1000) - $clock.ElapsedMilliseconds)
    $outputComplete = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),$remainingMs)
    foreach ($capture in @(@{task=$stdout;path=$StdoutPath},@{task=$stderr;path=$StderrPath})) {
      $content = if ($capture.task.IsCompletedSuccessfully) { $capture.task.GetAwaiter().GetResult() }
        else { '[output drain incomplete at enforced deadline; native logs retained]' }
      [IO.File]::WriteAllText($capture.path,$content,[Text.UTF8Encoding]::new($false))
    }
    if ($timedOut) { throw "[mir42-engine-row-deadline] $DeadlineSeconds seconds; stderr=$StderrPath" }
    if (-not $outputComplete) { throw "[mir42-engine-output-drain-deadline] $DeadlineSeconds seconds; stderr=$StderrPath" }
    if ($process.ExitCode -ne 0) { throw "[mir42-engine-row-failed] exit=$($process.ExitCode); stderr=$StderrPath" }
    return $process.ExitCode
  } finally {
    $process.StandardOutput.BaseStream.Dispose()
    $process.StandardError.BaseStream.Dispose()
    $process.Dispose()
  }
}

function Get-MIR42EngineLibraryBindings {
  param([string]$Path,[string[]]$Targets)
  if([string]::IsNullOrWhiteSpace($Path) -or -not(Test-Path -LiteralPath $Path -PathType Leaf)){
    throw '[mir42-engine-library-bindings-required] Supply a local JSON object mapping each selected target to its flat archive library.'
  }
  if((Get-Item -LiteralPath $Path).Length -gt 64KB){throw '[mir42-engine-library-bindings-size]'}
  $bindings=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json -AsHashtable
  if($bindings -isnot [Collections.IDictionary] -or $bindings.Count -ne $Targets.Count){throw '[mir42-engine-library-bindings-targets]'}
  foreach($target in $Targets){
    if($bindings[$target] -isnot [string] -or -not [IO.Path]::IsPathRooted($bindings[$target]) -or -not(Test-Path -LiteralPath $bindings[$target] -PathType Container)){
      throw "[mir42-engine-library-missing] $target requires an explicit existing flat library."
    }
    Assert-MIRLibraryPath -Path $bindings[$target]
    $bindings[$target]=(Resolve-Path -LiteralPath $bindings[$target]).Path
  }
  return $bindings
}

function Invoke-MIR42HistoricalFreshLoad {
  param(
    [Parameter(Mandatory)][ValidateSet('f017','f016','f015','f014','f013')][string]$Target,
    [Parameter(Mandatory)][string]$FactorioLine,
    [Parameter(Mandatory)][string]$Engine,
    [Parameter(Mandatory)][string]$EngineSha256,
    [Parameter(Mandatory)][string]$Candidate,
    [Parameter(Mandatory)][string]$CandidateSha256,
    [Parameter(Mandatory)][string]$LibraryDirectory,
    [Parameter(Mandatory)][string]$Version,
    [ValidateSet('4.2.0','4.2.1')][string]$SourceVersion='4.2.0',
    [Parameter(Mandatory)][string]$FreshRoot,
    [Parameter(Mandatory)][string]$SourceCommit,
    [Parameter(Mandatory)][int]$DeadlineSeconds
  )
  $identity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $Target.Substring(1) -SourceMinor 2 -SourcePatch ([int]($SourceVersion.Split('.')[2]))
  if ($FactorioLine -cne ('0.' + $Target.Substring(2)) -or $Version -cne [string]$identity.distribution_version) {
    throw "[mir42-$Target-historical-fresh-target-binding]"
  }
  $work = Join-Path $FreshRoot 'work'
  $userData = Join-Path $work 'user'
  New-Item -ItemType Directory -Force -Path $userData | Out-Null
  $save = Join-Path $work 'fresh.zip'
  $config = Join-Path $work 'config.ini'
  $log = Join-Path $userData 'factorio-current.log'
  $stdout = Join-Path $FreshRoot 'stdout.txt'
  $stderr = Join-Path $FreshRoot 'stderr.txt'
  $receipt = Join-Path $FreshRoot 'summary.json'
  Assert-MIRFactorioPathBudget -Path $save -Context "Historical $Target fresh-save path"
  if ((Get-MIR42EngineRunSha -Path $Engine) -cne $EngineSha256 -or
      (Get-MIR42EngineRunSha -Path $Candidate) -cne $CandidateSha256) {
    throw "[mir42-$Target-historical-fresh-input-drift]"
  }
  $engineRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Engine))
  $readData = Join-Path $engineRoot 'data'
  if (-not (Test-Path -LiteralPath (Join-Path $readData 'base') -PathType Container)) {
    throw "[mir42-$Target-historical-fresh-base-data]"
  }
  [IO.File]::WriteAllLines($config, @(
    '[path]',
    "read-data=$($readData.Replace('\','/'))",
    "write-data=$($userData.Replace('\','/'))",
    '[other]',
    'check-updates=false',
    'enable-new-mods=false'
  ), [Text.UTF8Encoding]::new($false))
  $activation=Start-MIRPackageLibraryActivation -LibraryDirectory $LibraryDirectory -EngineDataDirectory $readData `
    -ProfilePath (Join-Path $FreshRoot 'selection.json') -Version $Version -CandidateSha256 $CandidateSha256
  try {
  $mods=$activation.library
  $staged=@($activation.selected|Where-Object name -CEQ 'more-infinite-research')[0].path
  $modListSha=Get-MIR42EngineRunSha -Path (Join-Path $mods 'mod-list.json')
  $arguments = @('--config',$config,'--no-log-rotation')
  if ($FactorioLine -notin @('0.13','0.14')) { $arguments += '--disable-audio' }
  $arguments += @('--mod-directory',$mods,'--create',$save)
  Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $Engine -Arguments $arguments
  $null = Invoke-MIR42BoundedUpgrade -PowerShell $Engine -Arguments $arguments -StdoutPath $stdout -StderrPath $stderr -DeadlineSeconds $DeadlineSeconds -NativeActor
  if (-not (Test-Path -LiteralPath $save -PathType Leaf) -or
      -not (Test-Path -LiteralPath $log -PathType Leaf)) {
    throw "[mir42-$Target-historical-fresh-output-missing]"
  }
  $logText = Get-Content -Raw -LiteralPath $log
  $displayVersion = (($Version -split '\.') | ForEach-Object { [int]$_ }) -join '.'
  if ($logText -match '(?im)(^|\s)(Error|Failed to load mods|Failed to load mod|Invalid Mod|Couldn.t load|stack traceback)' -or
      -not $logText.Contains("Loading mod more-infinite-research $displayVersion") -or
      -not $logText.Contains('Factorio initialised') -or
      -not $logText.Contains('Creating new map') -or
      -not $logText.Contains('Map version ')) {
    throw "[mir42-$Target-historical-fresh-log-content] $log"
  }
  if ((Get-MIR42EngineRunSha -Path $Engine) -cne $EngineSha256 -or
      (Get-MIR42EngineRunSha -Path $staged) -cne $CandidateSha256) {
    throw "[mir42-$Target-historical-fresh-output-drift]"
  }
  $null=Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log
  $terminal=Complete-MIRLibraryActivation -Activation $activation
  $record = [ordered]@{
    schema=1;kind='MIR42HistoricalFreshLoadV1';status='passed';target=$Target
    source_commit=$SourceCommit;factorio_line=$FactorioLine
    engine=[ordered]@{path=$Engine;sha256=$EngineSha256}
    candidate=[ordered]@{path=$Candidate;sha256=$CandidateSha256;version=$Version}
    staged_candidate_sha256=(Get-MIR42EngineRunSha -Path $staged)
    config_sha256=(Get-MIR42EngineRunSha -Path $config)
    mod_list_sha256=$modListSha
    library_input_receipt=$terminal
    save=[ordered]@{path=$save;sha256=(Get-MIR42EngineRunSha -Path $save)}
    log=[ordered]@{path=$log;sha256=(Get-MIR42EngineRunSha -Path $log)}
    assertions=@('exact-engine','exact-candidate','fresh-save-created','exact-mod-loaded','map-created','healthy-log')
  }
  $normalized = ConvertTo-MIR4BootstrapCanonicalJson -Value $record | ConvertFrom-Json -Depth 100 -DateKind String
  $null = Write-MIR4BootstrapRecord -Record $normalized -Path $receipt
  $written = Get-Content -Raw -LiteralPath $receipt | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $written)) { throw "[mir42-$Target-historical-fresh-receipt-hash]" }
  return [pscustomobject][ordered]@{
    scenario='package-zip-base'
    receipt=[pscustomobject][ordered]@{path=$receipt;sha256=(Get-MIR42EngineRunSha -Path $receipt)}
    log=[pscustomobject][ordered]@{path=$log;sha256=(Get-MIR42EngineRunSha -Path $log)}
    stdout=[pscustomobject][ordered]@{path=$stdout;sha256=(Get-MIR42EngineRunSha -Path $stdout)}
    stderr=[pscustomobject][ordered]@{path=$stderr;sha256=(Get-MIR42EngineRunSha -Path $stderr)}
  }
  } finally {
    if(-not $activation.closed){$null=Complete-MIRLibraryActivation -Activation $activation}
  }
}

function New-MIR42EngineArchiveStage {
  param([Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)]$Row,
    [Parameter(Mandatory)][string]$OutputRoot,[Parameter(Mandatory)][string]$SourceVersion,
    [Parameter(Mandatory)][string]$SourceCommit,[Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)][AllowEmptyCollection()]$Leases)
  $stageRoot=Join-Path $OutputRoot "staged-assets/$Target"
  $stageDirectory=Join-Path $stageRoot 'archives'
  $staged=Join-Path $stageDirectory ([IO.Path]::GetFileName($Row.candidate))
  New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
  $inputs=@(
    [ordered]@{source_path=$Row.candidate;file_name=[IO.Path]::GetFileName($Row.candidate);expected_sha256=$Row.candidate_sha256;role='candidate';identity=@{target=$Target;version=$Row.to;source_version=$SourceVersion};provenance=@{kind='verified-candidate-manifest';source_commit=$SourceCommit};immutable=$true},
    [ordered]@{source_path=$Row.predecessor;file_name=[IO.Path]::GetFileName($Row.predecessor);expected_sha256=$Row.predecessor_sha256;role='predecessor';identity=@{target=$Target;version=$Row.from};provenance=@{kind='verified-predecessor-authority';source_version=$SourceVersion};immutable=$true}
  )
  $lease=New-MIRImmutableInputLease -RunRoot $stageRoot -StageDirectory $stageDirectory -Inputs $inputs -RequireHardLinks
  $Leases.Add($lease)
  Add-MIRNativeProbeImmutableLease -Context $Context -Lease $lease
  if ((Get-MIR42EngineRunSha -Path $staged) -cne $Row.candidate_sha256) { throw "[mir42-$Target-staged-candidate-hash]" }
  $Row.candidate=$staged
  if ((Get-MIR42EngineRunSha -Path $Row.predecessor) -cne $Row.predecessor_sha256) { throw "[mir42-$Target-locked-predecessor-hash]" }
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$candidateVersion = Get-MIR42EngineCandidateVersionContract -RepoRoot $repo -ManifestPath $CandidateManifestPath
$manifestPath = [string]$candidateVersion.path
$manifest = $candidateVersion.manifest
$sourceVersion = [string]$candidateVersion.source_version
$isNineTargetCandidate = [bool]$candidateVersion.nine_targets
$isFourTargetCandidate = [bool]$candidateVersion.four_targets
$packageAuthority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
$packageSourceSha = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
if ([string]$manifest.package_authority_sha256 -cne [string]$packageAuthority.record_sha256 -or
    [string]$manifest.package_source_sha256 -cne $packageSourceSha) {
  throw '[mir42-engine-candidate-package-authority]'
}
$head = (& git -C $repo rev-parse HEAD).Trim()
$tree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$dirty = @(& git -C $repo status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0 -or
    $head -cne [string]$manifest.source.commit -or $tree -cne [string]$manifest.source.tree) {
  throw '[mir42-engine-candidate-source-snapshot-mismatch]'
}
$candidateRoot = [IO.Path]::GetFullPath((Split-Path -Parent $manifestPath))
$out = [IO.Path]::GetFullPath($OutputRoot)
$buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build')).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
if (-not $out.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $out -PathType Leaf) -or
    ((Test-Path -LiteralPath $out -PathType Container) -and @(Get-ChildItem -LiteralPath $out -Force).Count -ne 0)) {
  throw '[mir42-engine-output-admission]'
}
$null = Assert-MIR4NoReparseAncestors -Root $repo -Path $out
$running=@(Get-Process -Name factorio -ErrorAction SilentlyContinue)
if($running.Count){throw '[mir42-engine-factorio-already-running]'}
$targets = if ($isNineTargetCandidate) { @($script:MIR42NineTargetEngineTargets) } else { @($script:MIR42ModernEngineTargets) }
$libraryBindings=Get-MIR42EngineLibraryBindings -Path $LibraryBindingsPath -Targets $targets
$resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $out -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB -UseExactOutputRoot
$inputLeases=[Collections.Generic.List[object]]::new()
trap {
  $failure=$_
  foreach($inputLease in $inputLeases){if(-not $inputLease.closed){try {$null=Complete-MIRImmutableInputLease -Lease $inputLease -Outcome failed} catch {}}}
  throw $failure
}

$inputAuthorityRelative = '.mir/releases/governance/mir4/MIR42-Direct-Predecessor-InputsV1.json'
$inputAuthorityPath = Assert-MIR42EngineRunFile -Path (Join-Path $repo $inputAuthorityRelative) -Label 'mir42-predecessor-authority'
$inputAuthority = Get-Content -Raw -LiteralPath $inputAuthorityPath | ConvertFrom-Json -Depth 100 -DateKind String
if (-not (Test-MIR4BootstrapRecordHash -Record $inputAuthority) -or
    [string]$inputAuthority.kind -cne 'MIR42DirectPredecessorInputsV1' -or
    [string]$inputAuthority.status -cne 'verified-published-v410-checksum-and-local-custody-private' -or
    [string]$inputAuthority.public_v410_checksums.tag -cne 'v4.1.0' -or
    [bool]$inputAuthority.release_transition_authority -or [bool]$inputAuthority.publication_authorized) {
  throw '[mir42-engine-predecessor-authority-invalid]'
}
$checksumRelative = [string]$inputAuthority.public_v410_checksums.path
if ($checksumRelative -cne '.mir/releases/governance/mir4/MIR42-v410-SHA256SUMS.txt') {
  throw '[mir42-engine-published-checksum-path]'
}
$checksumPath = Assert-MIR42EngineRunFile -Path (Join-Path $repo $checksumRelative) -Label 'mir42-published-checksums'
if ((Get-MIR42EngineRunSha -Path $checksumPath) -cne [string]$inputAuthority.public_v410_checksums.sha256 -or
    [string](& git -C $repo rev-parse 'refs/tags/v4.1.0').Trim() -cne [string]$inputAuthority.public_v410_checksums.tag_object -or
    [string](& git -C $repo rev-parse 'refs/tags/v4.1.0^{}').Trim() -cne [string]$inputAuthority.public_v410_checksums.tagged_commit) {
  throw '[mir42-engine-published-v410-identity]'
}
$signatureText = (& git -C $repo verify-tag v4.1.0 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or -not $signatureText.Contains([string]$inputAuthority.public_v410_checksums.verified_tag_fingerprint)) {
  throw '[mir42-engine-published-v410-tag-signature]'
}
$publishedRelease = (& gh api 'repos/Julesc013/more-infinite-research/releases/tags/v4.1.0' | Out-String) | ConvertFrom-Json -Depth 30 -DateKind String
if ($LASTEXITCODE -ne 0 -or [string]$publishedRelease.tag_name -cne 'v4.1.0' -or [bool]$publishedRelease.draft) {
  throw '[mir42-engine-published-v410-release-metadata]'
}
$checksumAsset = @($publishedRelease.assets | Where-Object { [string]$_.name -ceq 'SHA256SUMS.txt' })
if ($checksumAsset.Count -ne 1 -or
    [int64]$checksumAsset[0].id -ne [int64]$inputAuthority.public_v410_checksums.release_asset_id -or
    [string]$checksumAsset[0].digest -cne ('sha256:' + [string]$inputAuthority.public_v410_checksums.sha256).ToLowerInvariant() -or
    [int64]$checksumAsset[0].size -ne [int64]$inputAuthority.public_v410_checksums.release_asset_bytes -or
    [string]$checksumAsset[0].state -cne 'uploaded') {
  throw '[mir42-engine-published-v410-checksum-asset]'
}
$assetCheckRoot = Join-Path $repo ('build/v410-public-checksum-verification-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $assetCheckRoot | Out-Null
try {
  $null = & gh release download v4.1.0 -R Julesc013/more-infinite-research -p SHA256SUMS.txt -D $assetCheckRoot
  if ($LASTEXITCODE -ne 0) { throw '[mir42-engine-published-v410-checksum-download]' }
  $downloadedChecksum = Assert-MIR42EngineRunFile -Path (Join-Path $assetCheckRoot 'SHA256SUMS.txt') -Label 'mir42-published-v410-checksum-download'
  if ((Get-MIR42EngineRunSha -Path $downloadedChecksum) -cne [string]$inputAuthority.public_v410_checksums.sha256 -or
      [int64](Get-Item -LiteralPath $downloadedChecksum).Length -ne [int64]$checksumAsset[0].size) {
    throw '[mir42-engine-published-v410-checksum-download-content]'
  }
} finally {
  Remove-Item -LiteralPath $assetCheckRoot -Recurse -Force
}

$selected = [ordered]@{
  f210 = [ordered]@{ engine=$F210Engine; predecessor=$F210Predecessor; from='4.1.21000'; to='4.2.21000'; fixture='assert-upgrade-4-0-21000-to-4-1-21000'; engine_major='2.1' }
  f200 = [ordered]@{ engine=$F200Engine; predecessor=$F200Predecessor; from='4.1.20000'; to='4.2.20000'; fixture='assert-upgrade-4-0-20000-to-4-1-20000'; engine_major='2.0' }
  f110 = [ordered]@{ engine=$F110Engine; predecessor=$F110Predecessor; from='4.1.11000'; to='4.2.11000'; fixture='assert-upgrade-4-0-11000-to-4-1-11000'; engine_major='1.1' }
  f100 = [ordered]@{ engine=$F100Engine; predecessor=$F100Predecessor; from='4.1.10000'; to='4.2.10000'; fixture='assert-upgrade-4-0-10000-to-4-1-10000'; engine_major='1.0' }
}
foreach ($target in $script:MIR42ModernEngineTargets) {
  $selected[$target].to = [string](Get-MIR42ReleaseTargetIdentity -RepoRoot $repo -Target $target -SourceVersion $sourceVersion).distribution_version
}
if ((@($inputAuthority.targets | ForEach-Object { [string]$_.target }) -join '|') -cne ($script:MIR42ModernEngineTargets -join '|')) {
  throw '[mir42-engine-candidate-target-set]'
}
if ($isNineTargetCandidate) {
  $historicalHarness = Assert-MIR42HistoricalUpgradeHarness -RepoRoot $repo
  foreach ($target in $script:MIR42HistoricalEngineTargets) {
    $historical = Get-MIR42HistoricalEngineDescriptor -RepoRoot $repo -Target $target -SourceVersion $sourceVersion
    $historical.fixture = 'assert-upgrade-historical-terminal-to-mir42'
    $selected[$target] = $historical
  }
} else {
  $historicalHarness = $null
}

$maintenanceInputs = $null
if (-not [string]::IsNullOrWhiteSpace($PublishedMaintenancePredecessorManifestPath)) {
  if ($sourceVersion -cne '4.2.1' -or -not $isNineTargetCandidate) {
    throw '[mir42-engine-maintenance-predecessor-candidate-scope]'
  }
  $releaseText = (& gh api 'repos/Julesc013/more-infinite-research/releases/tags/v4.2.0-stable' | Out-String)
  if ($LASTEXITCODE -ne 0) { throw '[mir42-engine-maintenance-predecessor-release-readback]' }
  $maintenanceInputs = Get-MIR42PublishedMaintenancePredecessorInputs -RepoRoot $repo `
    -ManifestPath $PublishedMaintenancePredecessorManifestPath -ReleaseMetadata ($releaseText | ConvertFrom-Json -Depth 100 -DateKind String)
  foreach ($input in $maintenanceInputs.targets) {
    $target = [string]$input.target
    if ($target -in $script:MIR42ModernEngineTargets -and
        -not [IO.Path]::GetFullPath([string]$selected[$target].predecessor).Equals([string]$input.path,[StringComparison]::OrdinalIgnoreCase)) {
      throw ('[mir42-engine-maintenance-predecessor-explicit-input] ' + $target)
    }
    $selected[$target].predecessor = [string]$input.path
    $selected[$target].from = [string]$input.version
    $selected[$target].maintenance_predecessor = $input
  }
}

# Admit every input before starting the first Factorio process.
foreach ($target in $targets) {
  $row = $selected[$target]
  $isHistoricalTarget = $target -in $script:MIR42HistoricalEngineTargets
  $lock = if ($isHistoricalTarget) { $null } else { @($inputAuthority.targets | Where-Object { [string]$_.target -ceq $target })[0] }
  $row.engine = Assert-MIR42EngineRunFile -Path $row.engine -Label "mir42-$target-engine"
  $row.predecessor = Assert-MIR42EngineRunFile -Path $row.predecessor -Label "mir42-$target-predecessor"
  $row.engine_sha256 = Get-MIR42EngineRunSha -Path $row.engine
  $row.predecessor_sha256 = Get-MIR42EngineRunSha -Path $row.predecessor
  if ($isHistoricalTarget) {
    $historical = $row.historical
    if (-not $row.engine.Equals([IO.Path]::GetFullPath([string]$historical.engine.path),[StringComparison]::OrdinalIgnoreCase) -or
        $row.engine_sha256 -cne [string]$historical.engine.sha256) {
      throw "[mir42-$target-historical-input-lock]"
    }
    if ($null -eq $maintenanceInputs -and (
        -not $row.predecessor.Equals([IO.Path]::GetFullPath((Join-Path $repo ([string]$historical.predecessor.path))),[StringComparison]::OrdinalIgnoreCase) -or
        $row.predecessor_sha256 -cne [string]$historical.predecessor.sha256 -or
        [int64](Get-Item -LiteralPath $row.predecessor).Length -ne [int64]$historical.predecessor.bytes -or
        [string]$historical.predecessor.version -cne $row.from)) {
      throw "[mir42-$target-historical-input-lock]"
    }
  } else {
    if (-not $row.engine.Equals([IO.Path]::GetFullPath([string]$lock.engine.path),[StringComparison]::OrdinalIgnoreCase) -or
        $row.engine_sha256 -cne [string]$lock.engine.sha256) {
      throw "[mir42-$target-input-lock]"
    }
    if ($null -eq $maintenanceInputs -and (
      -not $row.predecessor.Equals([IO.Path]::GetFullPath([string]$lock.predecessor.path),[StringComparison]::OrdinalIgnoreCase) -or
      $row.predecessor_sha256 -cne [string]$lock.predecessor.sha256 -or
      [int64](Get-Item -LiteralPath $row.predecessor).Length -ne [int64]$lock.predecessor.bytes -or
      [string]$lock.predecessor.version -cne $row.from -or
      [string]$lock.published_checksum_sha256 -cne $row.predecessor_sha256 -or
      -not (Get-Content -LiteralPath $checksumPath | Where-Object { $_ -ceq "$($row.predecessor_sha256)  $([IO.Path]::GetFileName($row.predecessor))" }))) {
      throw "[mir42-$target-input-lock]"
    }
  }
  if ($null -ne $maintenanceInputs) {
    $predecessorLock = $row.maintenance_predecessor
    if (-not $row.predecessor.Equals([string]$predecessorLock.path,[StringComparison]::OrdinalIgnoreCase) -or
        $row.predecessor_sha256 -cne [string]$predecessorLock.sha256 -or
        [int64](Get-Item -LiteralPath $row.predecessor).Length -ne [int64]$predecessorLock.bytes -or
        $row.from -cne [string]$predecessorLock.version) {
      throw "[mir42-$target-maintenance-input-lock]"
    }
  }
  if ((Get-MIR42EngineRunArchiveVersion -Path $row.predecessor) -cne $row.from) {
    throw "[mir42-$target-predecessor-version]"
  }
  $row.engine_file_version = [string](Get-Item -LiteralPath $row.engine).VersionInfo.FileVersion
  $row.engine_product_version = [string](Get-Item -LiteralPath $row.engine).VersionInfo.ProductVersion
  if ($isHistoricalTarget) {
    # Terminal seals bind the exact binary digest. Old Factorio executables either append a
    # build number to FileVersion or expose no Windows version resource, so accept a present
    # ProductVersion only as an additional check and record the sealed semantic version.
    if (-not [string]::IsNullOrWhiteSpace($row.engine_product_version)) {
      $historicalProductVersion = if ($row.engine_product_version -match '^([0-9]+[.][0-9]+[.][0-9]+)') { [string]$Matches[1] } else { $row.engine_product_version }
      if ($historicalProductVersion -cne [string]$historical.engine.version) {
        throw "[mir42-$target-historical-engine-version] $($row.engine_product_version)"
      }
    }
    $row.engine_version = [string]$historical.engine.version
  } elseif (-not $row.engine_product_version.StartsWith($row.engine_major + '.', [StringComparison]::Ordinal) -or
      $row.engine_product_version -cne [string]$lock.engine.product_version -or
      $row.engine_file_version -cne [string]$lock.engine.file_version) {
    throw "[mir42-$target-engine-version] $($row.engine_product_version)"
  } else {
    $row.engine_version = $row.engine_file_version
  }
  $candidate = @($manifest.targets | Where-Object { [string]$_.target -ceq $target })[0]
  $targetRowPath = Assert-MIR42EngineRunFile -Path (Join-Path $candidateRoot ([string]$candidate.target_row_path)) -Label "mir42-$target-builder-row"
  $targetRow = Get-Content -Raw -LiteralPath $targetRowPath | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $targetRow) -or
      [string]$targetRow.target -cne $target -or
      [string]$targetRow.asset.sha256 -cne [string]$candidate.asset.sha256 -or
      [string]$targetRow.build_a_sha256 -cne [string]$candidate.asset.sha256 -or
      [string]$targetRow.build_b_sha256 -cne [string]$candidate.asset.sha256 -or
      -not [bool]$targetRow.deterministic_archive_bytes) {
    throw "[mir42-$target-builder-row-binding]"
  }
  if ($isHistoricalTarget) {
    foreach ($field in @('materializer','base_materializer_target','factorio_line','target_record','engine','predecessor','public_output_authorized','publication_authorized')) {
      if ($targetRow.PSObject.Properties.Name -notcontains $field) { throw "[mir42-$target-historical-builder-row-field] $field" }
    }
    $historical = $row.historical
    if ([string]$targetRow.materializer -cne 'historical-playtest-target' -or [string]$targetRow.base_materializer_target -cne 'f100' -or
        [string]$targetRow.factorio_line -cne [string]$historical.terminal_seal.target -or
        [string]$targetRow.target_record.path -cne [string]$historical.target_record.path -or [string]$targetRow.target_record.sha256 -cne [string]$historical.target_record.record_sha256 -or
        [string]$targetRow.engine.version -cne [string]$historical.engine.version -or [string]$targetRow.engine.sha256 -cne [string]$historical.engine.sha256 -or
        [string]$targetRow.predecessor.archive -cne [string]$historical.predecessor.path -or [string]$targetRow.predecessor.version -cne [string]$historical.predecessor.version -or [string]$targetRow.predecessor.sha256 -cne [string]$historical.predecessor.sha256 -or
        [bool]$targetRow.public_output_authorized -or [bool]$targetRow.publication_authorized) {
      throw "[mir42-$target-historical-builder-row-binding]"
    }
  }
  if ([string]$candidate.distribution_version -cne $row.to) { throw "[mir42-$target-candidate-version]" }
  $assetRelative = [string]$candidate.asset.path
  if ([IO.Path]::IsPathRooted($assetRelative) -or $assetRelative -match '(^|[\\/])[.][.]([\\/]|$)') {
    throw "[mir42-$target-candidate-asset-path]"
  }
  $row.candidate = Assert-MIR42EngineRunFile -Path (Join-Path $candidateRoot $assetRelative) -Label "mir42-$target-candidate"
  if (-not $row.candidate.StartsWith($candidateRoot.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
      (Get-MIR42EngineRunSha -Path $row.candidate) -cne [string]$candidate.asset.sha256) {
    throw "[mir42-$target-candidate-asset-hash]"
  }
  if ((Get-MIR42EngineRunArchiveVersion -Path $row.candidate) -cne $row.to) {
    throw "[mir42-$target-candidate-archive-version]"
  }
  $inventory = Get-MIR4ArchiveInventory -Path $row.candidate
  if ([string]$inventory.content_sha256 -cne [string]$candidate.content_sha256 -or
      [int]$inventory.entry_count -ne [int]$candidate.entry_count) {
    throw "[mir42-$target-candidate-content]"
  }
  $row.candidate_sha256 = [string]$candidate.asset.sha256
}
$pwsh = Assert-MIR42EngineRunFile -Path (Get-Command pwsh).Source -Label 'mir42-pwsh'
$harness = Assert-MIR42EngineRunFile -Path (Join-Path $repo 'tests/runtime/Test-MIRUpgrade.ps1') -Label 'mir42-upgrade-harness'
$runner = Assert-MIR42EngineRunFile -Path $PSCommandPath -Label 'mir42-engine-runner'
New-Item -ItemType Directory -Force -Path $out | Out-Null
foreach ($target in $targets) {
  $row = $selected[$target]
  New-MIR42EngineArchiveStage -Target $target -Row $row -OutputRoot $out -SourceVersion $sourceVersion -SourceCommit $head -Context $resources -Leases $inputLeases
}
$results = [Collections.Generic.List[object]]::new()
$processTotal = 0
foreach ($target in $targets) {
  $row = $selected[$target]
  $isHistoricalTarget = $target -in $script:MIR42HistoricalEngineTargets
  $rowRoot = Join-Path $out $target
  New-Item -ItemType Directory -Force -Path $rowRoot | Out-Null
  if ($isHistoricalTarget) {
    $freshRoot = Join-Path $rowRoot 'fresh-package-zip-base'
    New-Item -ItemType Directory -Force -Path $freshRoot | Out-Null
    $freshLoads = @(Invoke-MIR42HistoricalFreshLoad -Target $target -FactorioLine ([string]$row.historical.terminal_seal.target) `
      -Engine $row.engine -EngineSha256 $row.engine_sha256 -Candidate $row.candidate -CandidateSha256 $row.candidate_sha256 `
      -LibraryDirectory $libraryBindings[$target] `
      -Version $row.to -SourceVersion $sourceVersion -FreshRoot $freshRoot -SourceCommit $head -DeadlineSeconds $RowDeadlineSeconds)
    $processTotal++
  } else {
    $freshLoads = @(
    foreach ($scenario in $(if ($target -eq 'f210') { @('package-zip-base','package-zip-space-age') } else { @('package-zip-base') })) {
      $freshRoot = Join-Path $rowRoot "fresh-$scenario"
      New-Item -ItemType Directory -Force -Path $freshRoot | Out-Null
      $summaryPath = Join-Path $freshRoot 'summary.json'
      $freshStdout = Join-Path $freshRoot 'stdout.txt'
      $freshStderr = Join-Path $freshRoot 'stderr.txt'
      $freshArgs = @('-NoProfile','-File',(Join-Path $repo 'scripts/Invoke-MIRValidation.ps1'),
        '-ScenarioWorker','-Scenario',$scenario,'-FactorioBin',$row.engine,
        '-UserDataDir',(Join-Path $freshRoot 'work'),'-CandidateZip',$row.candidate,
        '-LibraryDirectory',$libraryBindings[$target],
        '-MaxParallel','1','-ValidationSummaryPath',$summaryPath)
      if ((Get-MIR42EngineRunSha -Path $row.engine) -cne $row.engine_sha256) {
        throw "[mir42-$target-$scenario-engine-drift-before]"
      }
      if ((Get-MIR42EngineRunSha -Path $row.candidate) -cne $row.candidate_sha256) {
        throw "[mir42-$target-$scenario-staged-candidate-drift-before]"
      }
      $null = Invoke-MIR42BoundedUpgrade -PowerShell $pwsh -Arguments $freshArgs -StdoutPath $freshStdout -StderrPath $freshStderr -DeadlineSeconds $RowDeadlineSeconds -NativeActor

      if ((Get-MIR42EngineRunSha -Path $row.engine) -cne $row.engine_sha256) {
        throw "[mir42-$target-$scenario-engine-drift-after]"
      }
      if ((Get-MIR42EngineRunSha -Path $row.candidate) -cne $row.candidate_sha256) {
        throw "[mir42-$target-$scenario-staged-candidate-drift-after]"
      }
      $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json -Depth 100 -DateKind String
      $candidateRow = @($manifest.targets | Where-Object { [string]$_.target -ceq $target })[0]
      if ([string]$summary.status -cne 'passed' -or [string]$summary.git_commit -cne $head -or
          [string]$summary.validation_package_sha256 -cne [string]$candidateRow.asset.sha256 -or
          [string]$summary.validation_package_content_sha256 -cne [string]$candidateRow.content_sha256 -or
          @($summary.expected_scenarios).Count -ne 1 -or [string]$summary.expected_scenarios[0] -cne $scenario -or
          @($summary.scenarios).Count -ne 1 -or [string]$summary.scenarios[0].status -cne 'passed') {
        throw "[mir42-$target-$scenario-fresh-summary-binding]"
      }
      $logPath = Assert-MIR42EngineRunFile -Path (Join-Path $freshRoot 'work/factorio-current.log') -Label "mir42-$target-$scenario-fresh-log"
      $logText = Get-Content -Raw -LiteralPath $logPath
      if (-not $logText.Contains("Loading mod more-infinite-research $($row.to)") -or
          -not $logText.Contains('Factorio initialised') -or -not $logText.Contains('Creating new map')) {
        throw "[mir42-$target-$scenario-fresh-log-content]"
      }
      $processTotal++
      [pscustomobject][ordered]@{
        scenario=$scenario
        receipt=[pscustomobject][ordered]@{path=$summaryPath;sha256=(Get-MIR42EngineRunSha -Path $summaryPath)}
        log=[pscustomobject][ordered]@{path=$logPath;sha256=(Get-MIR42EngineRunSha -Path $logPath)}
        stdout=[pscustomobject][ordered]@{path=$freshStdout;sha256=(Get-MIR42EngineRunSha -Path $freshStdout)}
        stderr=[pscustomobject][ordered]@{path=$freshStderr;sha256=(Get-MIR42EngineRunSha -Path $freshStderr)}
      }
    }
    )
  }
  $receiptPath = Join-Path $rowRoot 'upgrade.json'
  $stdoutPath = Join-Path $rowRoot 'harness-stdout.txt'
  $stderrPath = Join-Path $rowRoot 'harness-stderr.txt'
  $args = @('-NoProfile','-File',$harness,'-RepoRoot',$repo,'-FactorioBin',$row.engine,
    '-FromZip',$row.predecessor,'-ToZip',$row.candidate,'-FromVersion',$row.from,'-ToVersion',$row.to,
    '-FixtureName',$row.fixture,'-Archetype','base-default','-OutputPath',$receiptPath,
    '-LocalModLibraryDirs',$libraryBindings[$target],
    '-WorkRoot',(Join-Path $rowRoot 'work'),'-Retention','OnFailure',
    '-ExpectedPeakMemoryMiB',([string]$ExpectedPeakMemoryMiB),'-MaxNewOutputMiB',([string][int][Math]::Floor((Get-MIRNativeProbeRemainingOutputBytes -Context $resources)/1MB)))
  if ((Get-MIR42EngineRunSha -Path $row.candidate) -cne $row.candidate_sha256) { throw "[mir42-$target-staged-candidate-drift-before-upgrade]" }
  if ((Get-MIR42EngineRunSha -Path $row.engine) -cne $row.engine_sha256) { throw "[mir42-$target-engine-drift-before-upgrade]" }
  $exitCode = Invoke-MIR42BoundedUpgrade -PowerShell $pwsh -Arguments $args -StdoutPath $stdoutPath -StderrPath $stderrPath -DeadlineSeconds $RowDeadlineSeconds
  if ((Get-MIR42EngineRunSha -Path $row.engine) -cne $row.engine_sha256) { throw "[mir42-$target-engine-drift-after-upgrade]" }
  if ((Get-MIR42EngineRunSha -Path $row.candidate) -cne $row.candidate_sha256) { throw "[mir42-$target-staged-candidate-drift-after-upgrade]" }
  $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 50 -DateKind String
  $requiredAssertions = @('exact-candidate-normal-mod-directory-load','upgraded-save-reload-passed','upgraded-save-second-reload-passed')
  if ($isHistoricalTarget) {
    $requiredAssertions += @('historical-terminal-source-state-retained','historical-terminal-researched-level-retained',
      'historical-terminal-current-research-retained','historical-terminal-fractional-progress-retained',
      'historical-terminal-infinite-bonus-retained-where-supported','historical-terminal-global-state-retained')
  }
  $missingAssertions = @($requiredAssertions | Where-Object { $_ -cnotin @($receipt.assertions) })
  if ([string]$receipt.status -cne 'passed' -or [string]$receipt.git_commit -cne $head -or
      [string]$receipt.factorio_binary_sha256 -cne $row.engine_sha256 -or
      [string]$receipt.from.sha256 -cne $row.predecessor_sha256 -or
      [string]$receipt.to.sha256 -cne $row.candidate_sha256 -or
      [int]$receipt.factorio_processes -lt 4 -or
      $missingAssertions.Count -ne 0) {
    throw "[mir42-$target-upgrade-receipt-binding]"
  }
  $logs = @(
    foreach ($phase in @('create','load','reload','second-reload')) {
      $field = if ($phase -eq 'second-reload') { 'second_reload' } else { $phase }
      $logName = [string]$receipt."${field}_log"
      if ($logName -cne [IO.Path]::GetFileName($logName)) { throw "[mir42-$target-$phase-log-path]" }
      $path = Assert-MIR42EngineRunFile -Path (Join-Path $rowRoot $logName) -Label "mir42-$target-$phase-log"
      $sha = Get-MIR42EngineRunSha -Path $path
      if ($sha -cne [string]$receipt."${field}_log_sha256") { throw "[mir42-$target-$phase-log-hash]" }
      [pscustomobject][ordered]@{phase=$phase;path=$path;sha256=$sha}
    }
  )
  $processTotal += [int]$receipt.factorio_processes
  $resources.runs.Add([pscustomobject]@{kind='upgrade-worker';status='passed';stdout=$stdoutPath;stderr=$stderrPath;governor_owner='Test-MIRUpgrade';resource_policy=$receipt.resource_policy;resource_ledgers=@($receipt.resource_ledgers)})
  $execution = [ordered]@{
    executable_path=$row.engine;executable_sha256=$row.engine_sha256;version=$row.engine_version
    predecessor=[pscustomobject][ordered]@{path=$row.predecessor;sha256=$row.predecessor_sha256;version=$row.from}
    fresh_loads=$freshLoads
    harness_receipt=[pscustomobject][ordered]@{path=$receiptPath;sha256=(Get-MIR42EngineRunSha -Path $receiptPath)}
    harness_exit_code=$exitCode;logs=$logs;fresh_exact_load=$true;predecessor_upgrade=$true;reload_count=2
  }
  if ($isHistoricalTarget) { $execution.historical_terminal_authority = $row.historical }
  if ($null -ne $maintenanceInputs) { $execution.published_maintenance_predecessor = $row.maintenance_predecessor }
  $results.Add([pscustomobject][ordered]@{
    target=$target
    status='passed'
    archive=[pscustomobject][ordered]@{path=$row.candidate;sha256=(Get-MIR42EngineRunSha -Path $row.candidate)}
    engine_execution=[pscustomobject]$execution
  })
  Write-Host "[ok] $target engine upgrade and two reloads: $receiptPath"
}
$runKind = if ($null -ne $maintenanceInputs) { 'MIR42NineTargetMaintenanceEngineRunV1' } elseif ($isNineTargetCandidate) { 'MIR42NineTargetEngineRunV1' } else { 'MIR42FourTargetEngineRunV1' }
$runStatus = if ($null -ne $maintenanceInputs) { 'nine-target-maintenance-base-default-real-engine-probes-passed-private-unqualified' } elseif ($isNineTargetCandidate) { 'nine-target-base-default-real-engine-probes-passed-private-unqualified' } else { 'four-target-base-default-real-engine-probes-passed-private-unqualified' }
$runLabel = if ($isNineTargetCandidate) { 'nine-target' } else { 'four-target' }
$record = [ordered]@{
  schema=1
  kind=$runKind
  status=$runStatus
  source=[ordered]@{commit=$head;tree=$tree}
  candidate_manifest=[ordered]@{path=$manifestPath;sha256=(Get-MIR42EngineRunSha -Path $manifestPath);record_sha256=[string]$manifest.record_sha256}
  predecessor_authority=[ordered]@{path=$inputAuthorityPath;sha256=(Get-MIR42EngineRunSha -Path $inputAuthorityPath);record_sha256=[string]$inputAuthority.record_sha256}
  public_v410_checksum_asset=[ordered]@{release_id=[int64]$publishedRelease.id;asset_id=[int64]$checksumAsset[0].id;digest=[string]$checksumAsset[0].digest;bytes=[int64]$checksumAsset[0].size;download_verified=$true}
  runner=[ordered]@{path=$runner;sha256=(Get-MIR42EngineRunSha -Path $runner)}
  harness=[ordered]@{path=$harness;sha256=(Get-MIR42EngineRunSha -Path $harness)}
  targets=@($results.ToArray())
  factorio_processes=$processTotal
  release_qualification='not-performed'
  publication_authorized=$false
}
if ($isNineTargetCandidate) {
  $record.historical_upgrade_harness = $historicalHarness
  $historicalAuthorities = @(
    foreach ($target in $script:MIR42HistoricalEngineTargets) {
      [pscustomobject][ordered]@{target=$target;authority=$selected[$target].historical}
    }
  )
  if ($null -ne $maintenanceInputs) {
    $record.historical_target_authorities = $historicalAuthorities
    $record.published_maintenance_predecessor = $maintenanceInputs
  } else {
    $record.historical_terminal_predecessors = $historicalAuthorities
  }
}
$recordPath = Join-Path $out 'engine-run.json'
foreach($inputLease in $inputLeases){if(-not $inputLease.closed){$null=Complete-MIRImmutableInputLease -Lease $inputLease -Outcome passed}}
$resourceRecord=[ordered]@{kind='MIR42EngineRunResourceDiagnosticsV1';source_commit=$head;source_version=$sourceVersion;expected_peak_memory_bytes=$resources.peak_memory_bytes;max_new_output_bytes=$resources.max_new_output_bytes;shared_alias_bytes=$resources.shared_alias_bytes;memory_enforcement='sampled-watchdog-not-hard-cap';process_inventory=@($resources.runs);input_staging=@($inputLeases|ForEach-Object {$_.record});release_qualification='not-performed'}
$resourceJson=($resourceRecord|ConvertTo-Json -Depth 40)+"`n"
if([Text.Encoding]::UTF8.GetByteCount($resourceJson) -ge (Get-MIRNativeProbeRemainingOutputBytes -Context $resources)){throw '[mir441-resource-output-budget]'}
[IO.File]::WriteAllText((Join-Path $out 'engine-run.resources.json'),$resourceJson,[Text.UTF8Encoding]::new($false))
$normalizedRecord = ConvertTo-MIR4BootstrapCanonicalJson -Value $record | ConvertFrom-Json -Depth 100 -DateKind String
$normalizedRecord|Add-Member -NotePropertyName record_sha256 -NotePropertyValue (Get-MIR4BootstrapRecordSha256 -Record $normalizedRecord)
if([Text.Encoding]::UTF8.GetByteCount((ConvertTo-MIR4BootstrapCanonicalJson -Value $normalizedRecord)+"`n") -ge (Get-MIRNativeProbeRemainingOutputBytes -Context $resources -IncludeResultReserve)){throw '[mir441-resource-output-budget]'}
$null = Write-MIR4BootstrapRecord -Record $normalizedRecord -Path $recordPath
$writtenRecord = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json -Depth 100 -DateKind String
if (-not (Test-MIR4BootstrapRecordHash -Record $writtenRecord)) { throw '[mir42-engine-run-record-self-hash]' }
Write-Host "[ok] private $runLabel engine run: $recordPath"
