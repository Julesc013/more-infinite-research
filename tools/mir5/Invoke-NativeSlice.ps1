# Private MIR 5 native proof: an owned gear fixture over the existing flat
# archive library.  This is intentionally independent from MIR 4 compiler,
# packaging, and runtime command modules.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ArchiveLibrary,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$PlayerArchive,
  [Parameter(Mandatory)][string]$FixtureArchive,
  [Parameter(Mandatory)][string]$OutputRoot,
  [ValidateSet('Default','Tuned')][string]$Profile = 'Default',
  [ValidateRange(30,600)][int]$TimeoutSeconds = 180,
  [string]$ExpectedPlayerVersion = '5.0.21000',
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-NativeSlice {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "[mir5-native-slice] $Message" }
}

function Get-NativeSliceSha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-NativeSliceArchiveInfo {
  param([Parameter(Mandatory)][string]$Archive)
  Add-Type -AssemblyName System.IO.Compression
  $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
  try {
    $entries = @($zip.Entries | Where-Object { $_.FullName -match '^[^/]+/info[.]json$' })
    Assert-NativeSlice ($entries.Count -eq 1) "archive does not contain one rooted info.json: $Archive"
    $reader = [IO.StreamReader]::new($entries[0].Open())
    try { $info = $reader.ReadToEnd() | ConvertFrom-Json -AsHashtable } finally { $reader.Dispose() }
    $root = $entries[0].FullName.Substring(0, $entries[0].FullName.Length - 'info.json'.Length).TrimEnd('/')
    Assert-NativeSlice (-not [string]::IsNullOrWhiteSpace([string]$info.name) -and [string]$info.version -match '^\d+[.]\d+[.]\d+$') "archive has invalid mod identity: $Archive"
    return [pscustomobject]@{ path = (Resolve-Path -LiteralPath $Archive).Path; sha256 = Get-NativeSliceSha256 $Archive; info = $info; root = $root }
  } finally { $zip.Dispose() }
}

function Assert-NativeSliceInstalledArchive {
  param([Parameter(Mandatory)]$Archive, [Parameter(Mandatory)][string]$Library, [Parameter(Mandatory)][string]$Role)
  $installed = Join-Path $Library ([IO.Path]::GetFileName($Archive.path))
  Assert-NativeSlice (Test-Path -LiteralPath $installed -PathType Leaf) "$Role archive is not installed once in the selected direct library: $installed"
  Assert-NativeSlice ((Get-NativeSliceSha256 $installed) -ceq $Archive.sha256) "$Role archive bytes differ from its explicit input"
  return (Resolve-Path -LiteralPath $installed).Path
}

function Assert-NativeSliceFixtureArchive {
  param([Parameter(Mandatory)][string]$Archive, [Parameter(Mandatory)][string]$SourceDirectory, [Parameter(Mandatory)][string]$ExpectedVersion)
  $source = (Resolve-Path -LiteralPath $SourceDirectory).Path
  $sourceInfo = Get-Content -LiteralPath (Join-Path $source 'info.json') -Raw | ConvertFrom-Json -AsHashtable
  $archiveInfo = Get-NativeSliceArchiveInfo $Archive
  Assert-NativeSlice ($archiveInfo.info.name -ceq $sourceInfo.name -and $archiveInfo.info.version -ceq $ExpectedVersion) 'fixture archive identity differs from selected profile'
  Add-Type -AssemblyName System.IO.Compression
  $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
  try {
    foreach ($file in @(Get-ChildItem -LiteralPath $source -Recurse -File)) {
      $relative = [IO.Path]::GetRelativePath($source, $file.FullName).Replace('\','/')
      $entry = $zip.GetEntry($archiveInfo.root + '/' + $relative)
      Assert-NativeSlice ($null -ne $entry) "fixture archive is missing source member: $relative"
      if ($relative -ceq 'info.json') {
        $reader = [IO.StreamReader]::new($entry.Open())
        try { $actualInfo = $reader.ReadToEnd() | ConvertFrom-Json -AsHashtable } finally { $reader.Dispose() }
        foreach ($name in $sourceInfo.Keys) {
          if ($name -ceq 'version') { continue }
          Assert-NativeSlice (($actualInfo[$name] | ConvertTo-Json -Compress -Depth 16) -ceq ($sourceInfo[$name] | ConvertTo-Json -Compress -Depth 16)) "fixture archive changed info.json member '$name'"
        }
        continue
      }
      Assert-NativeSlice ($entry.Length -eq $file.Length) "fixture archive member size differs: $relative"
      $stream = $entry.Open()
      try { $actual = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)) } finally { $stream.Dispose() }
      Assert-NativeSlice ($actual -ceq (Get-NativeSliceSha256 $file.FullName)) "fixture archive member bytes differ: $relative"
    }
  } finally { $zip.Dispose() }
  return $archiveInfo
}

function Write-NativeSliceJson {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
  [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 32), [Text.UTF8Encoding]::new($false))
}

function Read-NativeSliceLiveLog {
  param([Parameter(Mandatory)][string]$Path)
  $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
  try {
    $reader = [IO.StreamReader]::new($stream)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
  } finally { $stream.Dispose() }
}

function Get-NativeSliceFatalDiagnostic {
  param([AllowNull()][string]$Text)
  if ([string]::IsNullOrEmpty($Text)) { return $null }
  return [regex]::Match($Text, '(?im)^\s*\d+[.]\d+\s+Error\b.*$|^Error while running event\b.*$|\bException at tick\b|\bnon-recoverable error\b|^stack traceback:$')
}

function Get-NativeSliceResult {
  param([Parameter(Mandatory)][string]$LogPath, [Parameter(Mandatory)][string]$Stage)
  $text = [IO.File]::ReadAllText($LogPath)
  $rows = @([regex]::Matches($text, '\[MIR5_GEAR_NATIVE\] RESULT (\{[^\r\n]+\})') | ForEach-Object { $_.Groups[1].Value | ConvertFrom-Json })
  $matches = @($rows | Where-Object { $_.stage -ceq $Stage })
  Assert-NativeSlice ($matches.Count -eq 1) "expected exactly one native fixture result for $Stage"
  return $matches[0]
}

function Assert-NativeSliceResult {
  param([Parameter(Mandatory)]$Result, [Parameter(Mandatory)][string]$Stage, [Parameter(Mandatory)]$Expected)
  Assert-NativeSlice ($Result.stage -ceq $Stage -and $Result.profile -ceq $Expected.name) "$Stage result profile differs"
  Assert-NativeSlice ($Result.technology -ceq 'recipe-prod-research_gears-1') "$Stage result technology differs"
  Assert-NativeSlice ($Result.completed_level -eq 1 -and $Result.next_level -eq 2) "$Stage researched level differs"
  Assert-NativeSlice ([Math]::Abs([double]$Result.effect_change - [double]$Expected.effect_change) -le 0.000001) "$Stage effect differs"
  Assert-NativeSlice ($Result.level_one_count -eq $Expected.level_one_count) "$Stage level-one count differs"
  Assert-NativeSlice ($Result.level_two_count -gt $Result.level_one_count -and $Result.level_three_count -gt $Result.level_two_count) "$Stage native count progression differs"
  Assert-NativeSlice ($Result.baseline_output -eq 100 -and $Result.researched_output -eq $Expected.researched_output) "$Stage physical gear production differs"
  Assert-NativeSlice ($Result.baseline_plates_inserted -eq 200 -and $Result.researched_plates_inserted -eq 200) "$Stage physical gear input witness differs"
}

function Invoke-NativeSliceStage {
  param(
    [Parameter(Mandatory)][string]$Stage,
    [Parameter(Mandatory)][string[]]$StageArguments,
    [scriptblock]$Completion = $null
  )
  $liveLog = Join-Path $userdata 'factorio-current.log'
  if (Test-Path -LiteralPath $liveLog) { Remove-Item -LiteralPath $liveLog -Force }
  $arguments = @('--config', $config, '--no-log-rotation', '--disable-audio', '--mod-directory', $activation.library) + $StageArguments
  Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $arguments
  $capturedLog = Join-Path $run ($Stage + '.factorio.log')
  $stdoutLog = Join-Path $run ($Stage + '.stdout.log')
  $stderrLog = Join-Path $run ($Stage + '.stderr.log')
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = $engine
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  $start.Environment['SteamAppId'] = '427520'
  $start.Environment['SteamGameId'] = '427520'
  foreach ($argument in $arguments) { [void]$start.ArgumentList.Add($argument) }
  $process = $null
  $stdoutTask = $null
  $stderrTask = $null
  $stdoutText = ''
  $stderrText = ''
  $completionObserved = $false
  $controlledKillAfterCompletion = $false
  $exitCode = $null
  try {
    $process = [Diagnostics.Process]::Start($start)
    # Begin draining both pipes before polling.  Waiting to read either stream
    # after Factorio exits can deadlock a verbose failed create/load stage.
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
      if ($process.HasExited) {
        $exitCode = $process.ExitCode
        if ($null -eq $Completion) { break }
        throw "native engine exited before completing $Stage with code $exitCode; diagnostics: $stdoutLog ; $stderrLog ; $capturedLog"
      }
      if (Test-Path -LiteralPath $liveLog -PathType Leaf) {
        try { $liveText = Read-NativeSliceLiveLog $liveLog } catch [IO.IOException] { $liveText = $null }
        $fatal = Get-NativeSliceFatalDiagnostic $liveText
        if ($null -ne $fatal -and $fatal.Success) {
          throw "native engine emitted a fatal diagnostic during ${Stage}: $($fatal.Value); diagnostics: $stdoutLog ; $stderrLog ; $capturedLog"
        }
        if ($null -ne $Completion -and $null -ne $liveText) {
          $completionObserved = [bool](& $Completion $liveText)
          if ($completionObserved) { break }
        }
      }
      Start-Sleep -Milliseconds 150
    }
    if ($null -eq $Completion -and -not $process.HasExited) { throw "native engine timed out during $Stage; diagnostics: $stdoutLog ; $stderrLog ; $capturedLog" }
    if ($null -ne $Completion -and -not $completionObserved) { throw "native engine did not complete $Stage within $TimeoutSeconds seconds; diagnostics: $stdoutLog ; $stderrLog ; $capturedLog" }
    if ($null -eq $Completion -and $exitCode -ne 0) { throw "native engine failed during $Stage with code $exitCode; diagnostics: $stdoutLog ; $stderrLog ; $capturedLog" }
  } finally {
    if ($null -ne $process) {
      if (-not $process.HasExited) {
        if ($null -ne $Completion -and $completionObserved) { $controlledKillAfterCompletion = $true }
        try { $process.Kill($true) } catch { $process.Kill() }
      }
      $process.WaitForExit()
      if ($null -eq $exitCode -and $process.HasExited) { $exitCode = $process.ExitCode }
      try {
        if ($null -ne $stdoutTask) { $stdoutText = $stdoutTask.GetAwaiter().GetResult() }
        if ($null -ne $stderrTask) { $stderrText = $stderrTask.GetAwaiter().GetResult() }
        [IO.File]::WriteAllText($stdoutLog, $stdoutText, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($stderrLog, $stderrText, [Text.UTF8Encoding]::new($false))
      } finally {
        # Failure paths must retain every native diagnostic that exists before
        # the outer activation restores the library controls.
        if (Test-Path -LiteralPath $liveLog -PathType Leaf) {
          Copy-Item -LiteralPath $liveLog -Destination $capturedLog -Force
        }
        $process.Dispose()
      }
    }
  }
  Assert-NativeSlice (Test-Path -LiteralPath $capturedLog -PathType Leaf) "native engine produced no captured Factorio log for $Stage"
  foreach ($diagnostic in @($capturedLog, $stdoutLog, $stderrLog)) {
    $fatal = Get-NativeSliceFatalDiagnostic ([IO.File]::ReadAllText($diagnostic))
    Assert-NativeSlice ($null -eq $fatal -or -not $fatal.Success) "native engine emitted a fatal diagnostic during ${Stage}: $($fatal.Value)"
  }
  if ($null -ne $Completion) {
    Assert-NativeSlice ($completionObserved -and $controlledKillAfterCompletion) "native completion must be terminated by the harness while the process remains alive"
  }
  $loaded = Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $capturedLog -LatestInvocation
  return [pscustomobject]@{ stage = $Stage; log = $capturedLog; log_sha256 = Get-NativeSliceSha256 $capturedLog; stdout_log = $stdoutLog; stderr_log = $stderrLog; exit_code = $exitCode; completion_observed = $completionObserved; controlled_kill_after_completion = $controlledKillAfterCompletion; loaded = $loaded }
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
# LibraryActivation is intentionally reusable and receives its immutable-input
# primitives from its caller.  Keep the native slice on that minimal generic
# contract rather than importing any MIR 4 compiler or runner surface.
$mirCompatIdentityModule = New-Module -Name MIR5NativeSliceInputIdentity -ArgumentList (Join-Path $repo 'tools/lib/validation/ImmutableInputStaging.ps1') -ScriptBlock {
  param($Path)
  . $Path
  Export-ModuleMember -Function Get-MIRImmutableInputSha256,Get-MIRImmutableInputFileIdentity,Assert-MIRCheckoutHardLinkBoundary
}
Import-Module $mirCompatIdentityModule -Force
. (Join-Path $repo 'tools/lib/compatibility/LibraryActivation.ps1')
$library = (Resolve-Path -LiteralPath $ArchiveLibrary).Path
$engine = (Resolve-Path -LiteralPath $FactorioBin).Path
Assert-NativeSlice (Test-Path -LiteralPath $engine -PathType Leaf) 'Factorio executable is missing'
$engineRoot = (Get-Item -LiteralPath $engine).Directory.Parent.Parent.FullName
$engineData = Join-Path $engineRoot 'data'
$base = Get-Content -LiteralPath (Join-Path $engineData 'base/info.json') -Raw | ConvertFrom-Json -AsHashtable
Assert-NativeSlice ($base.version -ceq '2.1.23') "native slice requires exact current base 2.1.23; got $($base.version)"

$profiles = @{
  Default = [ordered]@{ name = 'default'; fixture_version = '0.1.0'; effect_change = 0.10; level_one_count = 8000; researched_output = 110; formula = '8000*2^(L-1)'; time = 60 }
  Tuned = [ordered]@{ name = 'tuned'; fixture_version = '0.2.0'; effect_change = 0.20; level_one_count = 100; researched_output = 120; formula = '(100+25*(L-1))*1.5^(L-1)'; time = 30 }
}
$expected = $profiles[$Profile]

$player = Get-NativeSliceArchiveInfo $PlayerArchive
Assert-NativeSlice ($player.info.name -ceq 'more-infinite-research' -and $player.info.version -ceq $ExpectedPlayerVersion) 'explicit player archive is not the private MIR 5 package'
$installedPlayer = Assert-NativeSliceInstalledArchive -Archive $player -Library $library -Role 'player'
$fixtureSource = Join-Path $repo 'tests/mir5/fixtures/gear'
$fixture = Assert-NativeSliceFixtureArchive -Archive $FixtureArchive -SourceDirectory $fixtureSource -ExpectedVersion $expected.fixture_version
$installedFixture = Assert-NativeSliceInstalledArchive -Archive $fixture -Library $library -Role 'fixture'

# The explicit inventory call documents the exact modern selection mechanism:
# same name+version duplicates are refused by the generic activator, while the
# profile selects one enabled version per mod name and disables other versions.
$inventory = @(Get-MIRLibraryInventory -LibraryDirectory $library -EngineDataDirectory $engineData)
$mirRows = @($inventory | Where-Object { $_.name -ceq 'more-infinite-research' })
Assert-NativeSlice (@($mirRows | Where-Object { $_.version -ceq $ExpectedPlayerVersion }).Count -eq 1) 'library does not have exactly one selected MIR 5 name/version'
Assert-NativeSlice (@($inventory | Where-Object { $_.name -ceq $fixture.info.name -and $_.version -ceq $fixture.info.version }).Count -eq 1) 'library does not have exactly one selected fixture name/version'

& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 2 -MaxEntriesPerRoot 500 | Out-Host
$output = [IO.Path]::GetFullPath($OutputRoot)
[IO.Directory]::CreateDirectory($output) | Out-Null
$run = Join-Path $output ('gear-native-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($run) | Out-Null
$userdata = Join-Path $run 'userdata'
[IO.Directory]::CreateDirectory((Join-Path $userdata 'saves')) | Out-Null
$config = Join-Path $run 'config.ini'
$configText = "[path]`nread-data=$($engineData.Replace('\','/'))`nwrite-data=$($userdata.Replace('\','/'))`n`n[other]`nenable-new-mods=false`ncheck-updates=false`nenable-steam-networking=false`ndisable-blueprint-storage=true`nenable-blueprint-storage-cloud-sync=false`n"
[IO.File]::WriteAllText($config, $configText, [Text.UTF8Encoding]::new($false))
$server = Join-Path $run 'server-settings.json'
Write-NativeSliceJson -Path $server -Value ([ordered]@{ name = 'MIR 5 private gear native slice'; description = ''; tags = @(); max_players = 1; visibility = [ordered]@{ public = $false; lan = $false }; username = ''; password = ''; token = ''; game_password = ''; require_user_verification = $false; max_upload_in_kilobytes_per_second = 0; max_upload_slots = 5; minimum_latency_in_ticks = 0; ignore_player_limit_for_returning_players = $false; allow_commands = 'admins-only'; autosave_interval = 0; autosave_slots = 1; afk_autokick_interval = 0; auto_pause = $false; only_admins_can_pause_the_game = $false })
$selection = Join-Path $run 'selection.json'
Write-NativeSliceJson -Path $selection -Value ([ordered]@{ mods = @(
  [ordered]@{ name = 'base'; version = $base.version; enabled = $true },
  [ordered]@{ name = $player.info.name; version = $player.info.version; enabled = $true },
  [ordered]@{ name = $fixture.info.name; version = $fixture.info.version; enabled = $true }
) })
$hashes = @{}
$hashes[[IO.Path]::GetFileName($installedPlayer)] = $player.sha256
$hashes[[IO.Path]::GetFileName($installedFixture)] = $fixture.sha256

$record = [ordered]@{
  kind = 'MIR5GearNativeSliceV1'; status = 'prepared'; profile = $expected; run = $run
  source_commit = [string](& git -C $repo rev-parse HEAD)
  source_dirty = (@(& git -C $repo status --porcelain=v1).Count -gt 0)
  harness_sha256 = Get-NativeSliceSha256 $PSCommandPath
  library_activation_sha256 = Get-NativeSliceSha256 (Join-Path $repo 'tools/lib/compatibility/LibraryActivation.ps1')
  immutable_input_helpers_sha256 = Get-NativeSliceSha256 (Join-Path $repo 'tools/lib/validation/ImmutableInputStaging.ps1')
  engine = [ordered]@{ path = $engine; sha256 = Get-NativeSliceSha256 $engine; base_version = $base.version }
  player_archive = [ordered]@{ input = $player.path; installed = $installedPlayer; sha256 = $player.sha256; name = $player.info.name; version = $player.info.version }
  fixture_archive = [ordered]@{ input = $fixture.path; installed = $installedFixture; sha256 = $fixture.sha256; name = $fixture.info.name; version = $fixture.info.version }
  direct_library_selection = [ordered]@{ mechanism = 'exact-profile-name-version-and-sha256'; same_name_version = 'rejected-by-activation-inventory'; distinct_mir_versions = 'one-enabled-version-row-per-name'; selected_mir_versions = @($mirRows | ForEach-Object version | Sort-Object) }
  dependency_payload_bytes_copied = 0; archive_links_created = 0; archive_extractions = 0; native_qualification = $false
}
$activation = $null
try {
  $activation = Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $engineData -ProfilePath $selection -ArchiveHashes $hashes -SettingsMode Defaults
  $seed = Join-Path $userdata 'saves/seed.zip'
  $record.create = Invoke-NativeSliceStage -Stage 'create' -StageArguments @('--create', $seed)
  Assert-NativeSlice (Test-Path -LiteralPath $seed -PathType Leaf) 'create stage did not write a seed save'
  $complete = Join-Path $userdata ('saves/' + 'mir5-gear-native-complete.zip')
  $completion = {
    param([string]$LogText)
    return (Test-Path -LiteralPath $complete -PathType Leaf) -and $LogText.Contains('[MIR5_GEAR_NATIVE] RESULT ') -and $LogText.Contains('Saving finished')
  }.GetNewClosure()
  $record.production = Invoke-NativeSliceStage -Stage 'production' -StageArguments @('--server-settings', $server, '--bind', '127.0.0.1', '--start-server', $seed) -Completion $completion
  Assert-NativeSlice ($record.production.completion_observed) 'production stage did not save completed native proof'
  $initial = Get-NativeSliceResult -LogPath $record.production.log -Stage 'initial'
  Assert-NativeSliceResult -Result $initial -Stage 'initial' -Expected $expected
  $saveSha256 = Get-NativeSliceSha256 $complete
  $record.reloads = @()
  foreach ($ordinal in 1..2) {
    $reload = Invoke-NativeSliceStage -Stage ('reload-' + $ordinal) -StageArguments @('--benchmark', $complete, '--benchmark-ticks', '1', '--benchmark-runs', '1', '--benchmark-sanitize')
    $result = Get-NativeSliceResult -LogPath $reload.log -Stage 'reload'
    Assert-NativeSliceResult -Result $result -Stage 'reload' -Expected $expected
    Assert-NativeSlice ((Get-NativeSliceSha256 $complete) -ceq $saveSha256) "cold reload $ordinal changed the completed save"
    $record.reloads += [ordered]@{ ordinal = $ordinal; stage = $reload; result = $result; save_sha256 = $saveSha256; save_byte_identical = $true }
  }
  $record.status = 'passed-private-native-gear-slice'
  $record.native_qualification = $true
} catch {
  $record.status = 'failed'
  $record.failure = $_.Exception.Message
  throw
} finally {
  if ($null -ne $activation -and -not $activation.closed) {
    $record.library_control_restoration = Complete-MIRLibraryActivation -Activation $activation
  }
  Write-NativeSliceJson -Path (Join-Path $run 'receipt.json') -Value $record
}
