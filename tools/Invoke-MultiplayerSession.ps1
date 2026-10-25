# Shared guarded process lifecycle for the two explicit private F200 scenarios.
# It runs only under the governed native-probe parent. The parent prepares and
# validates the selected library, configs, and player-data files before calling
# this script. Spec fields: engine, engine_sha256, archive_library, workroot,
# seed_save, seed_sha256, server_config, server_settings, server_write_data,
# port, rcon_port, rcon_password, clients, expected_screenshots. Screenshot
# entries are absolute client write-data patterns: availability/initial/settled/rejoin/restart-*.png
# for each locale.
[CmdletBinding()]
param(
  [Parameter(Mandatory, ParameterSetName='session')][string]$SpecPath,
  [Parameter(Mandatory, ParameterSetName='selfcheck')][switch]$SelfCheck,
  [Parameter(Mandatory, ParameterSetName='selfcheck')][string]$CheckFile,
  [Parameter(Mandatory, ParameterSetName='selfcheck')][string]$CheckDirectory,
  [Parameter(Mandatory, ParameterSetName='rconselfcheck')][switch]$RconSelfCheck,
  [Parameter(Mandatory, ParameterSetName='rconselfcheck')][int]$RconCheckPort,
  [Parameter(Mandatory, ParameterSetName='rconselfcheck')][string]$RconCheckPassword
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib/validation/OwnedProcessMemorySampler.ps1')

function Assert-Session([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "[mir5-multiplayer-session] $Message" }
}
function Get-SessionHash([string]$Path) {
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
function Get-ProcessMemoryObservationOptIn([hashtable]$Spec,[string]$FixtureCase) {
  $collect = $false
  if ($Spec.ContainsKey('process_memory_observations')) {
    Assert-Session ($Spec.process_memory_observations -is [bool]) 'process memory observation flag must be Boolean'
    $collect = [bool]$Spec.process_memory_observations
  }
  Assert-Session (-not $collect -or $FixtureCase -cin @('library-multiplayer','library-paired-browser')) 'process memory observations require a named Library fixture'
  return $collect
}
function Test-Within([string]$Root, [string]$Path) {
  $relative = [IO.Path]::GetRelativePath($Root, $Path)
  return $relative -ne '..' -and -not $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar) -and -not [IO.Path]::IsPathRooted($relative)
}
function Assert-NoReparse([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force
  while ($null -ne $item) {
    Assert-Session (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "reparse point is not allowed: $($item.FullName)"
    $item = if ($item -is [IO.DirectoryInfo]) { $item.Parent } else { $item.Directory }
  }
}
function Resolve-Existing([string]$Path, [ValidateSet('Leaf','Container')][string]$Type, [string]$Label) {
  Assert-Session (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path -PathType $Type)) "$Label is absent or has the wrong type"
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  Assert-NoReparse $resolved
  return $resolved
}
function Resolve-BuildInput([string]$Path, [ValidateSet('Leaf','Container')][string]$Type, [string]$Label) {
  $resolved = Resolve-Existing $Path $Type $Label
  Assert-Session (Test-Within $buildRoot $resolved) "$Label is outside checkout build"
  return $resolved
}
function Resolve-BuildOutput([string]$Path, [string]$Label) {
  Assert-Session (-not [string]::IsNullOrWhiteSpace($Path)) "$Label is absent"
  $full = [IO.Path]::GetFullPath($Path)
  Assert-Session (Test-Within $buildRoot $full) "$Label is outside checkout build"
  $parent = [IO.Path]::GetDirectoryName($full)
  while (-not (Test-Path -LiteralPath $parent)) {
    $next = [IO.Path]::GetDirectoryName($parent)
    Assert-Session ($next -ne $parent) "$Label has no existing parent"
    $parent = $next
  }
  [void](Resolve-BuildInput $parent 'Container' "$Label parent")
  return $full
}
function Assert-Under([string]$Root, [string]$Path, [string]$Label) {
  Assert-Session (Test-Within $Root $Path) "$Label is outside its declared root"
}
function Test-SaveReady([string]$Path) {
  $stream = $null; $zip = $null
  try {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
    return $zip.Entries.Count -gt 0
  } catch { return $false }
  finally {
    if ($null -ne $zip) { $zip.Dispose() }
    if ($null -ne $stream) { $stream.Dispose() }
  }
}
function Test-Png1280x720([string]$Path) {
  $stream = $null
  try {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    if ($stream.Length -lt 36) { return $false }
    $bytes = [byte[]]::new(24); $read = $stream.Read($bytes, 0, $bytes.Length)
    if ($read -ne 24 -or (@($bytes[0..7]) -join ',') -cne '137,80,78,71,13,10,26,10') { return $false }
    if ([Text.Encoding]::ASCII.GetString($bytes, 12, 4) -cne 'IHDR') { return $false }
    $width = [int]$bytes[16] * 16777216 + [int]$bytes[17] * 65536 + [int]$bytes[18] * 256 + [int]$bytes[19]
    $height = [int]$bytes[20] * 16777216 + [int]$bytes[21] * 65536 + [int]$bytes[22] * 256 + [int]$bytes[23]
    # A complete native PNG ends with the zero-length IEND chunk and its CRC.
    $stream.Seek(-12, [IO.SeekOrigin]::End) | Out-Null
    $iend = [byte[]]::new(12)
    return $width -eq 1280 -and $height -eq 720 -and $stream.Read($iend, 0, $iend.Length) -eq 12 -and
      (@($iend) -join ',') -ceq '0,0,0,0,73,69,78,68,174,66,96,130'
  } catch { return $false }
  finally { if ($null -ne $stream) { $stream.Dispose() } }
}
function Assert-NoFatal([string]$Text, [string]$Label) {
  $fatal = [regex]::Match($Text, '(?im)^\s*\d+[.]\d+\s+Error\b|^Error while running event\b|\bException at tick\b|\bnon-recoverable error\b|^stack traceback:$|\bdesync(?:hronization)?\b')
  Assert-Session (-not $fatal.Success) "native fatal or desync in ${Label}: $($fatal.Value)"
}
function Close-ProcessMemoryObservation($Record) {
  if ($null -eq $processMemorySampler) { return }
  $property = $Record.PSObject.Properties['memory_observation']
  if ($null -ne $property -and $null -ne $property.Value) {
    Complete-MIROwnedProcessMemoryProcess -Sampler $processMemorySampler -Registration $property.Value
  }
}
function Complete-Record($Record) {
  if ($Record.closed) { return }
  Close-ProcessMemoryObservation $Record
  Assert-Session $Record.process.HasExited "cannot complete live process $($Record.name)"
  $Record.process.WaitForExit()
  $failure = $null
  try {
    foreach ($copy in @($Record.copy_tasks)) { $null = $copy.GetAwaiter().GetResult() }
  }
  catch { $failure = $_ }
  finally {
    foreach ($stream in @($Record.output_streams)) {
      try { $stream.Flush() } finally { $stream.Dispose() }
    }
  }
  $Record.exit_code = $Record.process.ExitCode
  $Record.process.Dispose()
  $Record.closed = $true
  if ($null -ne $failure) { throw $failure }
  Assert-NoFatal ((Read-LogText $Record.stdout) + [Environment]::NewLine + (Read-LogText $Record.stderr)) $Record.name
}
function Stop-Record($Record) {
  if ($null -eq $Record -or $Record.closed) { return }
  Close-ProcessMemoryObservation $Record
  $Record.expected_stop = $true
  if (-not $Record.process.HasExited) {
    try { $Record.process.Kill($true) } catch { $Record.process.Kill() }
  }
  Assert-Session $Record.process.WaitForExit(10000) "owned process did not stop: $($Record.name)"
  Complete-Record $Record
}
function Start-Native([string]$Name, [string[]]$Arguments) {
  $stdout = Resolve-BuildOutput (Join-Path $workroot ("phase-$Name.stdout.log")) "$Name stdout"
  $stderr = Resolve-BuildOutput (Join-Path $workroot ("phase-$Name.stderr.log")) "$Name stderr"
  Assert-Session (-not (Test-Path -LiteralPath $stdout) -and -not (Test-Path -LiteralPath $stderr)) "$Name output already exists"
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = $engine
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  foreach ($argument in $Arguments) { [void]$start.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
  $streams = [Collections.Generic.List[IO.FileStream]]::new()
  $started = $false
  try {
    $started = $process.Start()
    Assert-Session $started "failed to start $Name"
    foreach ($path in @($stdout,$stderr)) {
      $streams.Add([IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read))
    }
    $copies = @(
      $process.StandardOutput.BaseStream.CopyToAsync($streams[0]),
      $process.StandardError.BaseStream.CopyToAsync($streams[1])
    )
    $record = [pscustomobject]@{
      name=$Name; process=$process; stdout=$stdout; stderr=$stderr
      copy_tasks=$copies; output_streams=$streams.ToArray(); expected_stop=$false; closed=$false; exit_code=$null
    }
    if ($null -ne $processMemorySampler) {
      $match = [regex]::Match($Name, '^(?:server-(initial|restart)|client-(initial|rejoin|restart)-(en|de))$')
      if (-not $match.Success) {
        Set-MIROwnedProcessMemoryIncomplete -Sampler $processMemorySampler -Reason 'record-name-contract'
      } else {
        $phase = if ($match.Groups[1].Success) { [string]$match.Groups[1].Value } else { [string]$match.Groups[2].Value }
        $role = if ($match.Groups[1].Success) { 'server' } else { 'client-' + [string]$match.Groups[3].Value }
        $registration = Register-MIROwnedProcessMemoryProcess -Sampler $processMemorySampler -Phase $phase -Role $role -Process $process
        $record | Add-Member -NotePropertyName memory_observation -NotePropertyValue $registration
      }
    }
    [void]$records.Add($record)
    return $record
  }
  catch {
    foreach ($stream in @($streams)) { $stream.Dispose() }
    if ($started -and -not $process.HasExited) {
      try { $process.Kill($true) } catch { $process.Kill() }
      [void]$process.WaitForExit(10000)
    }
    $process.Dispose()
    throw
  }
}
function Read-LiveText {
  $parts = [Collections.Generic.List[string]]::new()
  foreach ($path in $liveLogs) {
    $text = Read-SharedText $path
    if ($null -ne $text) { $parts.Add($text) }
  }
  return ($parts -join [Environment]::NewLine)
}
function Read-SharedText([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $stream = $null; $reader = $null
  try {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = [IO.StreamReader]::new($stream, [Text.UTF8Encoding]::new($false), $true)
    return $reader.ReadToEnd()
  } catch [IO.IOException] { return $null }
  finally {
    if ($null -ne $reader) { $reader.Dispose() }
    elseif ($null -ne $stream) { $stream.Dispose() }
  }
}
function Read-LogText([string]$Path) {
  $text = Read-SharedText $Path
  if ($null -eq $text) { return '' }
  return $text
}
function Test-PairedBrowserBytePrefix([byte[]]$Prefix, [byte[]]$Value) {
  if ($Prefix.Length -gt $Value.Length) { return $false }
  for ($index = 0; $index -lt $Prefix.Length; $index++) {
    if ($Prefix[$index] -ne $Value[$index]) { return $false }
  }
  return $true
}
function Save-PairedBrowserServerPhaseLog([string]$Source, [ValidateSet('initial','restart')][string]$Phase, [string]$InitialLog = '') {
  $sourcePath = Resolve-BuildInput $Source 'Leaf' "paired Browser $Phase server log"
  $sourceItem = Get-Item -LiteralPath $sourcePath
  $maximumBytes = 8MB
  Assert-Session ($sourceItem.Length -le $maximumBytes) "paired Browser $Phase server log exceeds 8 MiB"
  $destination = Resolve-BuildOutput (Join-Path $workroot ("paired-browser-server-" + $Phase + ".factorio-current.log")) "paired Browser $Phase server log snapshot"
  Assert-Session (-not (Test-Path -LiteralPath $destination)) "paired Browser $Phase server log snapshot already exists"
  [byte[]]$sourceBytes = [IO.File]::ReadAllBytes($sourcePath)
  [byte[]]$phaseBytes = $sourceBytes
  if ($Phase -ceq 'restart' -and -not [string]::IsNullOrWhiteSpace($InitialLog)) {
    $initialPath = Resolve-BuildInput $InitialLog 'Leaf' 'paired Browser initial server log snapshot'
    [byte[]]$initialBytes = [IO.File]::ReadAllBytes($initialPath)
    Assert-Session ($initialBytes.Length -le $maximumBytes) 'paired Browser retained initial server log exceeds 8 MiB'
    if (Test-PairedBrowserBytePrefix $initialBytes $sourceBytes) {
      Assert-Session ($sourceBytes.Length -gt $initialBytes.Length) 'paired Browser restart server log has no post-initial bytes'
      $phaseBytes = [byte[]]::new($sourceBytes.Length - $initialBytes.Length)
      [Array]::Copy($sourceBytes, $initialBytes.Length, $phaseBytes, 0, $phaseBytes.Length)
    }
  }
  [IO.File]::WriteAllBytes($destination, $phaseBytes)
  $copied = Resolve-BuildInput $destination 'Leaf' "paired Browser $Phase server log snapshot"
  Assert-Session ((Get-Item -LiteralPath $copied).Length -eq $phaseBytes.Length) "paired Browser $Phase server log snapshot length differs"
  [byte[]]$copiedBytes = [IO.File]::ReadAllBytes($copied)
  Assert-Session (Test-PairedBrowserBytePrefix $phaseBytes $copiedBytes) "paired Browser $Phase server log snapshot bytes differ"
  return $copied
}
function Write-RconInt32([IO.Stream]$Stream, [int]$Value) {
  $bytes = [BitConverter]::GetBytes($Value)
  if (-not [BitConverter]::IsLittleEndian) { [Array]::Reverse($bytes) }
  $Stream.Write($bytes, 0, $bytes.Length)
}
function Read-RconExact([IO.Stream]$Stream, [int]$Count) {
  Assert-Session ($Count -ge 0 -and $Count -le 65536) 'RCON packet read length is invalid'
  $bytes = [byte[]]::new($Count)
  $offset = 0
  while ($offset -lt $Count) {
    $read = $Stream.Read($bytes, $offset, $Count - $offset)
    Assert-Session ($read -gt 0) 'RCON connection closed during packet read'
    $offset += $read
  }
  return ,$bytes
}
function Convert-RconInt32([byte[]]$Bytes) {
  Assert-Session ($Bytes.Length -eq 4) 'RCON integer encoding is invalid'
  if ([BitConverter]::IsLittleEndian) { return [BitConverter]::ToInt32($Bytes, 0) }
  $copy = [byte[]]$Bytes.Clone()
  [Array]::Reverse($copy)
  return [BitConverter]::ToInt32($copy, 0)
}
function Write-RconPacket([IO.Stream]$Stream, [int]$Id, [int]$Type, [string]$Payload) {
  $body = [Text.UTF8Encoding]::new($false).GetBytes($Payload)
  Assert-Session ($body.Length -le 65526) 'RCON payload is too large'
  Write-RconInt32 $Stream (10 + $body.Length)
  Write-RconInt32 $Stream $Id
  Write-RconInt32 $Stream $Type
  $Stream.Write($body, 0, $body.Length)
  $Stream.WriteByte(0)
  $Stream.WriteByte(0)
  $Stream.Flush()
}
function Read-RconPacket([IO.Stream]$Stream) {
  $length = Convert-RconInt32 (Read-RconExact $Stream 4)
  Assert-Session ($length -ge 10 -and $length -le 65536) 'RCON packet length is invalid'
  $packet = Read-RconExact $Stream $length
  Assert-Session ($packet[$length - 2] -eq 0 -and $packet[$length - 1] -eq 0) 'RCON packet terminators are invalid'
  $id = Convert-RconInt32 ([byte[]]$packet[0..3])
  $type = Convert-RconInt32 ([byte[]]$packet[4..7])
  return [pscustomobject]@{ id=$id; type=$type }
}
function Invoke-LoopbackRconKicks([int]$Port, [string]$Password) {
  $tcp = [Net.Sockets.TcpClient]::new()
  $stream = $null
  try {
    $tcp.SendTimeout = 5000
    $tcp.ReceiveTimeout = 5000
    $connect = $tcp.ConnectAsync([Net.IPAddress]::Loopback, $Port)
    Assert-Session ($connect.Wait(5000)) 'RCON loopback connection timed out'
    $connect.GetAwaiter().GetResult()
    $stream = $tcp.GetStream()
    $stream.ReadTimeout = 5000
    $stream.WriteTimeout = 5000
    $requestId = 43101
    Write-RconPacket $stream $requestId 3 $Password
    $auth = $null
    foreach ($attempt in 1..2) {
      $packet = Read-RconPacket $stream
      if ($packet.type -eq 2) { $auth = $packet; break }
      Assert-Session ($packet.type -eq 0 -and $packet.id -eq $requestId) 'RCON authentication response differs'
    }
    Assert-Session ($null -ne $auth -and $auth.id -eq $requestId) 'RCON authentication failed'
    foreach ($name in @('MIR5English','MIR5Deutsch')) {
      $requestId++
      Write-RconPacket $stream $requestId 2 ("/kick $name MIR5-rejoin-test")
      $response = Read-RconPacket $stream
      Assert-Session ($response.id -eq $requestId -and $response.type -eq 0) 'RCON kick response differs'
    }
  }
  finally {
    if ($null -ne $stream) { $stream.Dispose() }
    $tcp.Dispose()
  }
}
function Assert-Active {
  foreach ($record in $records) {
    if (-not $record.closed -and -not $record.expected_stop -and $record.process.HasExited) {
      Complete-Record $record
      throw "native process exited unexpectedly: $($record.name), code $($record.exit_code)"
    }
  }
  if ($null -ne $processMemorySampler) { Add-MIROwnedProcessMemorySample -Sampler $processMemorySampler }
  Assert-NoFatal (Read-LiveText) 'live native logs'
}
function Test-LibraryInteger([object]$Value) {
  return $Value -is [int] -or $Value -is [long]
}
function Assert-LibraryWitnessBoolean([object]$Witness, [string]$Field, [bool]$Expected, [string]$Stage) {
  $property = $Witness.PSObject.Properties[$Field]
  Assert-Session ($null -ne $property -and $property.Value -is [bool] -and $property.Value -eq $Expected) "$Stage Library witness $Field differs"
}
function Assert-LibraryWitnessInteger([object]$Witness, [string]$Field, [int]$Expected, [string]$Stage) {
  $property = $Witness.PSObject.Properties[$Field]
  Assert-Session ($null -ne $property -and (Test-LibraryInteger $property.Value) -and [int64]$property.Value -eq $Expected) "$Stage Library witness $Field differs"
}
function Get-LibraryWitnessVersionTarget([hashtable]$Spec, [string]$FixtureCase) {
  if ($FixtureCase -cne 'library-multiplayer') { return $null }
  Assert-Session ($Spec.ContainsKey('library_target') -and $Spec.library_target -is [string]) 'functional Library session target is absent or malformed'
  switch ([string]$Spec.library_target) {
    'f200' { return [pscustomobject]@{ base='2.0.77'; mir='5.0.20000' } }
    'f210' { return [pscustomobject]@{ base='2.1.23'; mir='5.0.21000' } }
    default { throw '[mir5-multiplayer-session] unsupported functional Library session target' }
  }
}
function Assert-LibraryWitnessVersion([object]$Witness, [object]$Expected, [string]$Stage) {
  $base = $Witness.PSObject.Properties['base_version']
  $mir = $Witness.PSObject.Properties['mir_version']
  Assert-Session ($null -ne $Expected -and $null -ne $base -and $base.Value -is [string] -and $base.Value -ceq $Expected.base -and $null -ne $mir -and $mir.Value -is [string] -and $mir.Value -ceq $Expected.mir) "$Stage Library witness version differs"
}
function Assert-LibraryLiveRefresh([object]$Witness, [string]$Stage) {
  $property = $Witness.PSObject.Properties['live_refresh']
  Assert-Session ($null -ne $property -and $property.Value -is [pscustomobject]) "$Stage Library live refresh is absent or malformed"
  $live = $property.Value
  Assert-LibraryWitnessInteger $live 'real_lab_completions' 2 $Stage
  Assert-LibraryWitnessBoolean $live 'native_laboratory_completion_by_script' $false $Stage
  $started = $live.PSObject.Properties['native_research_started_events']
  Assert-Session ($null -ne $started -and (Test-LibraryInteger $started.Value) -and [int64]$started.Value -ge 2) "$Stage Library witness native_research_started_events differs"
  $queue = @($live.queue_lengths_observed)
  Assert-Session ($queue.Count -eq 3 -and (Test-LibraryInteger $queue[0]) -and [int64]$queue[0] -eq 2 -and (Test-LibraryInteger $queue[1]) -and [int64]$queue[1] -eq 1 -and (Test-LibraryInteger $queue[2]) -and [int64]$queue[2] -eq 0) "$Stage Library witness queue_lengths_observed differs"
  Assert-LibraryWitnessInteger $live 'native_research_cancelled_events' 1 $Stage
  Assert-LibraryWitnessInteger $live 'native_foreign_force_created_events' 1 $Stage
  Assert-LibraryWitnessInteger $live 'gear_level' 3 $Stage
  $productivity = $live.PSObject.Properties['gear_productivity']
  Assert-Session ($null -ne $productivity -and $productivity.Value -is [double] -and [Math]::Abs([double]$productivity.Value - 0.2) -le 0.0000001) "$Stage Library witness gear_productivity differs"
  Assert-LibraryWitnessInteger $live 'science_consumed_per_named_pack' 2 $Stage
  Assert-LibraryWitnessBoolean $live 'fixture_accelerates_gear_count_and_time_only' $true $Stage
  Assert-LibraryWitnessBoolean $live 'ordinary_tuning_qualified' $false $Stage
  Assert-LibraryWitnessBoolean $live 'root_and_query_identity_preserved' $true $Stage
  Assert-LibraryWitnessBoolean $live 'cross_force_view_state_preserved' $true $Stage
}
function Get-StageMarker([string]$Text, [string]$Stage, [int]$ExpectedJoins) {
  Assert-Session ($Stage -cin @('ready','rejoin-ready','restart-ready','completed')) "unsupported stage: $Stage"
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($match in [regex]::Matches($Text, ('\['+[regex]::Escape($markerPrefix)+'\] RESULT (\{[^\r\n]+\})'))) {
    try { $row = $match.Groups[1].Value | ConvertFrom-Json }
    catch { continue } # A FileShare.ReadWrite read can end during an appended marker.
    if ($row.case -ceq $fixtureCase -and $row.stage -ceq $Stage) { $rows.Add($row) }
  }
  if ($rows.Count -eq 0) { return $null }
  Assert-Session ($rows.Count -eq 1 -and $rows[0].status -ceq 'passed') "stage witness differs: $Stage"
  $witness = $rows[0].witnesses
  if($fixtureCase-ceq'library-multiplayer') {
    Assert-LibraryWitnessInteger $witness 'actual_join_events' $ExpectedJoins $Stage
    Assert-LibraryWitnessBoolean $witness 'two_connected_clients_required' $true $Stage
    Assert-LibraryWitnessBoolean $witness 'distinct_personal_query_and_selection' $true $Stage
    Assert-LibraryWitnessBoolean $witness 'initial_native_snapshot_immutable' $true $Stage
    Assert-LibraryWitnessBoolean $witness 'initial_settled_without_reopen' ($Stage -cne 'ready') $Stage
    $settleTicks = $witness.PSObject.Properties['initial_settle_ticks']
    if ($Stage -ceq 'ready') {
      Assert-Session ($null -eq $settleTicks) "$Stage Library witness initial_settle_ticks must be omitted"
    } else {
      Assert-LibraryWitnessInteger $witness 'initial_settle_ticks' 60 $Stage
    }
    Assert-LibraryWitnessVersion $witness $libraryWitnessVersionTarget $Stage
    $liveProperty = $witness.PSObject.Properties['live_refresh']
    Assert-Session ($null -ne $liveProperty -and $liveProperty.Value -is [pscustomobject]) "$Stage Library live refresh is absent or malformed"
    $live = $liveProperty.Value
    if($Stage-ceq'ready') {
      Assert-LibraryWitnessBoolean $live 'native_laboratory_completion_by_script' $false $Stage
      Assert-LibraryWitnessInteger $live 'science_consumed_per_named_pack' 2 $Stage
      Assert-LibraryWitnessBoolean $live 'fixture_accelerates_gear_count_and_time_only' $true $Stage
      Assert-LibraryWitnessBoolean $live 'ordinary_tuning_qualified' $false $Stage
      Assert-LibraryWitnessBoolean $live 'root_and_query_identity_preserved' $true $Stage
      Assert-LibraryWitnessBoolean $live 'cross_force_view_state_preserved' $true $Stage
      Assert-LibraryWitnessInteger $live 'gear_level' 1 $Stage
      $productivity = $live.PSObject.Properties['gear_productivity']
      Assert-Session ($null -ne $productivity -and (Test-LibraryInteger $productivity.Value) -and [int64]$productivity.Value -eq 0) 'ready Library gear_productivity differs'
      Assert-LibraryWitnessInteger $witness 'screenshot_calls' 0 $Stage
      Assert-LibraryWitnessBoolean $witness 'availability_terminal_labels_checked' $false $Stage
    } else {
      Assert-LibraryLiveRefresh $witness $Stage
      Assert-LibraryWitnessBoolean $witness 'first_open' $true $Stage
      Assert-LibraryWitnessBoolean $witness 'search' $true $Stage
      Assert-LibraryWitnessBoolean $witness 'refresh' $true $Stage
      $captures=if($Stage-ceq'rejoin-ready'){6}elseif($Stage-ceq'restart-ready'){8}else{10}
      Assert-LibraryWitnessInteger $witness 'screenshot_calls' $captures $Stage
      Assert-LibraryWitnessBoolean $witness 'availability_terminal_labels_checked' $true $Stage
      if($Stage-cne'rejoin-ready'){Assert-LibraryWitnessBoolean $witness 'reopen' $true $Stage}
    }
  } else {
    Assert-Session ($witness.actual_join_events -eq $ExpectedJoins) "$Stage witness join count differs"
    Assert-Session ($witness.two_connected_clients_required -eq $true) "$Stage witness lacks native two-client checks"
    foreach($field in @('runtime_owned_state_checked','physical_rates_checked','foreign_offsets_preserved')) {
      $expected=$Stage-cne'ready'
      Assert-Session ($witness.PSObject.Properties[$field] -and $witness.$field -eq $expected) "$Stage witness lacks scripted-effects $field"
    }
  }
  return $rows[0]
}
function Assert-PairedBrowserInteger([object]$Value, [int]$Expected, [string]$Field, [string]$Stage) {
  Assert-Session ((Test-LibraryInteger $Value) -and [int64]$Value -eq $Expected) "$Stage paired Browser $Field differs"
}
function Assert-PairedBrowserBoolean([object]$Value, [bool]$Expected, [string]$Field, [string]$Stage) {
  Assert-Session ($Value -is [bool] -and $Value -eq $Expected) "$Stage paired Browser $Field differs"
}
function Get-PairedBrowserStageMarker([string]$Text, [string]$Stage, [string]$ExpectedArm) {
  $expectations = @{
    'ready' = @{ status='ready'; joins=0; actions=0; screenshots=0 }
    'first-open' = @{ status='observed'; joins=2; actions=2; screenshots=2 }
    'search' = @{ status='observed'; joins=2; actions=2; screenshots=4 }
    'refresh' = @{ status='observed'; joins=2; actions=2; screenshots=6 }
    'restart-ready' = @{ status='ready'; joins=2; actions=2; screenshots=6 }
    'reopen' = @{ status='observed'; joins=4; actions=2; screenshots=8 }
    'completed' = @{ status='passed'; joins=4; actions=2; screenshots=8 }
  }
  Assert-Session $expectations.ContainsKey($Stage) "unsupported paired Browser stage: $Stage"
  $rows = [Collections.Generic.List[object]]::new()
  $matches = [regex]::Matches($Text, '\[MIR5_LIBRARY_PAIRED_BROWSER\] ([^\r\n]+)(?:\r?\n|$)')
  foreach ($match in $matches) {
    $raw = $match.Groups[1].Value
    try { $row = $raw | ConvertFrom-Json }
    catch {
      $atEnd = $match.Index + $match.Length -eq $Text.Length
      if ($atEnd -and -not $Text.EndsWith("`n")) { continue }
      throw '[mir5-multiplayer-session] paired Browser marker is malformed'
    }
    Assert-Session (($row.schema -is [long] -or $row.schema -is [int]) -and [int64]$row.schema -eq 1 -and $row.case -ceq 'library-paired-browser') 'paired Browser marker identity differs'
    Assert-Session ($row.stage -is [string] -and $expectations.ContainsKey($row.stage)) 'paired Browser marker stage differs'
    if ($row.stage -ceq $Stage) { $rows.Add($row) }
  }
  if ($rows.Count -eq 0) { return $null }
  Assert-Session ($rows.Count -eq 1) "paired Browser marker is duplicated: $Stage"
  $row = $rows[0]
  $expected = $expectations[$Stage]
  Assert-Session ($row.status -is [string] -and $row.status -ceq $expected.status) "$Stage paired Browser status differs"
  Assert-Session ($row.arm -is [string] -and $row.arm -ceq $ExpectedArm) "$Stage paired Browser arm differs"
  Assert-PairedBrowserInteger $row.join_events $expected.joins 'join_events' $Stage
  Assert-PairedBrowserInteger $row.action_call_count $expected.actions 'action_call_count' $Stage
  Assert-PairedBrowserInteger $row.screenshot_calls $expected.screenshots 'screenshot_calls' $Stage
  Assert-PairedBrowserBoolean $row.native_snapshot_unchanged $true 'native_snapshot_unchanged' $Stage
  Assert-PairedBrowserBoolean $row.profiler_observation_only $true 'profiler_observation_only' $Stage
  Assert-PairedBrowserBoolean $row.performance_acceptance $false 'performance_acceptance' $Stage
  return $row
}
function Get-PairedBrowserProfilerMarkers([string]$Text, [string[]]$ExpectedActions) {
  $allowed = @('first_open','search','refresh','reopen')
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($match in [regex]::Matches($Text, '\[MIR5_LIBRARY_PROFILE\] ([^\r\n]+)(?:\r?\n|$)')) {
    $raw = $match.Groups[1].Value
    $parsed = [regex]::Match($raw, '^(first_open|search|refresh|reopen)\s+.+$')
    Assert-Session $parsed.Success 'paired Browser profiler marker grammar differs'
    $rows.Add([pscustomobject]@{ action=[string]$parsed.Groups[1].Value; raw_line=$match.Value.TrimEnd("`r","`n") })
  }
  foreach ($action in $allowed) {
    $count = @($rows | Where-Object { $_.action -ceq $action }).Count
    $expected = if ($action -in $ExpectedActions) { 1 } else { 0 }
    Assert-Session ($count -eq $expected) "paired Browser profiler action differs: $action"
  }
  return @($rows)
}
function Wait-For([string]$Description, [scriptblock]$Predicate) {
  while ([DateTime]::UtcNow -lt $deadline) {
    Assert-Active
    $value = & $Predicate (Read-LiveText)
    if ($null -ne $value -and $value -ne $false) { return $value }
    $delayMilliseconds = 200
    if ($null -ne $processMemorySampler) {
      $delayMilliseconds = Get-MIROwnedProcessMemorySleepMilliseconds -Sampler $processMemorySampler -MaximumDelayMilliseconds $delayMilliseconds
    }
    Start-Sleep -Milliseconds $delayMilliseconds
  }
  throw "timed out waiting for $Description; native diagnostics are in $workroot"
}
function Find-Screenshots([string[]]$Stages) {
  $files = [Collections.Generic.List[string]]::new()
  $indices = @{}
  foreach ($expected in @($screenshotPatterns | Where-Object { $_.stage -in $Stages })) {
    $parent = [IO.Path]::GetDirectoryName($expected.path)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { return $null }
    $matches = @(Get-ChildItem -LiteralPath $parent -File | Where-Object { $_.Name -like $expected.leaf })
    if ($matches.Count -ne 1) { return $null }
    $path = Resolve-BuildInput $matches[0].FullName 'Leaf' 'captured screenshot'
    if (-not (Test-Png1280x720 $path)) { return $null }
    $filenamePattern = if($fixtureCase -ceq 'library-paired-browser'){'^(first-open|search|refresh|reopen)-([12])[.]png$'}else{'^(availability|initial|settled|rejoin|restart)-([12])[.]png$'}
    $match = [regex]::Match($matches[0].Name, $filenamePattern)
    Assert-Session $match.Success 'captured screenshot filename differs'
    if ($indices.ContainsKey($expected.client) -and $indices[$expected.client] -ne $match.Groups[2].Value) {
      throw "screenshot player index changed for $($expected.client)"
    }
    $indices[$expected.client] = $match.Groups[2].Value
    $files.Add($path)
  }
  if (($fixtureCase -ceq 'library-multiplayer' -and $Stages.Count -eq 5) -or ($fixtureCase -ceq 'library-paired-browser' -and $Stages.Count -eq 4)) {
    Assert-Session ($indices.Count -eq 2 -and (@($indices.Values | Select-Object -Unique)).Count -eq 2) 'client screenshot player indexes are not distinct and stable'
  }
  return [pscustomobject]@{files=@($files);indexes=$indices}
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$buildRoot = Resolve-Existing (Join-Path $repoRoot 'build') 'Container' 'checkout build'
if ($SelfCheck) {
  $file = Resolve-BuildInput $CheckFile 'Leaf' 'self-check build file'
  $directory = Resolve-BuildInput $CheckDirectory 'Container' 'self-check build directory'
  $candidate = Resolve-BuildOutput (Join-Path $directory 'mir5-multiplayer-self-check.output') 'self-check output'
  [pscustomobject]@{status='passed-nonnative-helper-self-check';file=$file;directory=$directory;output_candidate=$candidate}
  return
}
if ($RconSelfCheck) {
  Assert-Session ($RconCheckPort -gt 0 -and $RconCheckPort -le 65535) 'RCON self-check port is invalid'
  Assert-Session ($RconCheckPassword -cmatch '^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$') 'RCON self-check password must be a temporary GUID'
  Invoke-LoopbackRconKicks $RconCheckPort $RconCheckPassword
  [pscustomobject]@{status='passed-nonnative-rcon-self-check';port=$RconCheckPort;commands=2}
  return
}
$specPath = Resolve-BuildInput $SpecPath 'Leaf' 'session spec'
$spec = Get-Content -LiteralPath $specPath -Raw | ConvertFrom-Json -AsHashtable
$fixtureCase=if($spec.ContainsKey('case')){[string]$spec.case}else{'library-multiplayer'}
Assert-Session ($fixtureCase-cin@('library-multiplayer','library-paired-browser','scripted-effects-multiplayer')) 'unsupported multiplayer fixture case'
$libraryWitnessVersionTarget=Get-LibraryWitnessVersionTarget $spec $fixtureCase
$collectProcessMemoryObservations = Get-ProcessMemoryObservationOptIn -Spec $spec -FixtureCase $fixtureCase
$markerPrefix=switch($fixtureCase){'library-multiplayer'{'MIR5_LIBRARY_MULTIPLAYER'};'library-paired-browser'{'MIR5_LIBRARY_PAIRED_BROWSER'};default{'MIR5_SCRIPTED_EFFECTS_MULTIPLAYER'}}
$clientGraphics=@(if($fixtureCase-ceq'scripted-effects-multiplayer'){'--force-graphics-preset';'low';'--video-memory-usage';'low'})
foreach ($field in @('engine','engine_sha256','archive_library','workroot','seed_save','seed_sha256','server_config','server_settings','server_write_data','port','rcon_port','rcon_password','clients','expected_screenshots')) {
  Assert-Session $spec.ContainsKey($field) "session spec lacks $field"
}
$engine = Resolve-Existing ([string]$spec.engine) 'Leaf' 'engine'
Assert-Session ([string]$spec.engine_sha256 -cmatch '^[A-Fa-f0-9]{64}$') 'engine hash is invalid'
Assert-Session ((Get-SessionHash $engine) -ceq ([string]$spec.engine_sha256).ToUpperInvariant()) 'engine hash differs'
$library = Resolve-Existing ([string]$spec.archive_library) 'Container' 'archive library'
$workroot = Resolve-BuildInput ([string]$spec.workroot) 'Container' 'workroot'
$seed = Resolve-BuildInput ([string]$spec.seed_save) 'Leaf' 'seed save'
Assert-Session ([string]$spec.seed_sha256 -cmatch '^[A-Fa-f0-9]{64}$') 'seed hash is invalid'
$seedHash = Get-SessionHash $seed
Assert-Session ($seedHash -ceq ([string]$spec.seed_sha256).ToUpperInvariant()) 'seed save hash differs'
$serverConfig = Resolve-BuildInput ([string]$spec.server_config) 'Leaf' 'server config'
$serverSettings = Resolve-BuildInput ([string]$spec.server_settings) 'Leaf' 'server settings'
$serverWriteData = Resolve-BuildInput ([string]$spec.server_write_data) 'Container' 'server write-data'
$serverPort=[int]$spec.port
Assert-Session ($serverPort -ge 1024 -and $serverPort -le 65535) 'server port must be an OS-assigned loopback user port'
$rconPort = [int]$spec.rcon_port
Assert-Session ($rconPort -ge 1024 -and $rconPort -le 65535) 'RCON port must be an OS-assigned loopback user port'
$rconPassword = [string]$spec.rcon_password
Assert-Session ($rconPassword -cmatch '^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$') 'RCON password must be a temporary GUID'
$settings = Get-Content -LiteralPath $serverSettings -Raw | ConvertFrom-Json -AsHashtable
Assert-Session ($settings.ContainsKey('require_user_verification') -and $settings.require_user_verification -eq $false) 'server settings must disable user verification'
$clients = @($spec.clients)
Assert-Session ($clients.Count -eq 2) 'session requires exactly two clients'
$names = [Collections.Generic.List[string]]::new()
$configs = [Collections.Generic.List[string]]::new()
$writeData = [Collections.Generic.List[string]]::new()
$ports = [Collections.Generic.List[int]]::new()
foreach ($client in $clients) {
  foreach ($field in @('name','locale','config','write_data','port')) { Assert-Session $client.ContainsKey($field) "client spec lacks $field" }
  Assert-Session ([string]$client.name -cmatch '^[A-Za-z0-9_-]+$' -and -not $names.Contains([string]$client.name)) 'client names must be distinct literal identifiers'
  Assert-Session ([string]$client.locale -in @('en','de')) 'client locale must be en or de'
  $null = $names.Add([string]$client.name)
  $client.config = Resolve-BuildInput ([string]$client.config) 'Leaf' ("client $($client.name) config")
  $client.write_data = Resolve-BuildInput ([string]$client.write_data) 'Container' ("client $($client.name) write-data")
  Assert-Session (-not $configs.Contains([string]$client.config) -and -not $writeData.Contains([string]$client.write_data)) 'client configs and write-data must be distinct'
  $null = $configs.Add([string]$client.config); $null = $writeData.Add([string]$client.write_data)
  Assert-Session ([int]$client.port -ge 1024 -and [int]$client.port -le 65535 -and [int]$client.port -ne $serverPort -and -not $ports.Contains([int]$client.port)) 'client loopback user ports must be distinct from each other and server'
  $null = $ports.Add([int]$client.port)
}
Assert-Session (($clients.locale | Sort-Object) -join ',' -ceq 'de,en') 'two client locales must be en and de'
Assert-Session ((@($names | Sort-Object) -join ',') -ceq 'MIR5Deutsch,MIR5English') 'two client identities must be MIR5English and MIR5Deutsch'
$pairedArm=$null
if($fixtureCase -ceq 'library-paired-browser'){
  Assert-Session ($spec.ContainsKey('paired_arm') -and $spec.paired_arm -is [string] -and $spec.paired_arm -cin @('published','mir5')) 'paired Browser session arm differs'
  $pairedArm=[string]$spec.paired_arm
}
$restartSave = Resolve-BuildOutput (Join-Path $serverWriteData ('saves/mir5-'+$fixtureCase+'-restart.zip')) 'restart save'
$finalSave = Resolve-BuildOutput (Join-Path $serverWriteData 'saves/mir5-native-complete.zip') 'final save'
$sessionPath = Resolve-BuildOutput (Join-Path $workroot 'session.json') 'session output'
$screenshotPatterns = [Collections.Generic.List[object]]::new()
$patterns = @($spec.expected_screenshots | ForEach-Object { Resolve-BuildOutput ([string]$_) 'expected screenshot pattern' })
if($fixtureCase-ceq'library-multiplayer') {
 Assert-Session ($patterns.Count -eq 10 -and (@($patterns | Select-Object -Unique)).Count -eq 10) 'session requires ten distinct screenshot patterns'
 foreach ($client in $clients) {
  $root = [IO.Path]::GetFullPath((Join-Path $client.write_data 'script-output/mir5-library-multiplayer'))
  $clientPatterns = @($patterns | Where-Object { Test-Within $root $_ })
  Assert-Session ($clientPatterns.Count -eq 5) "client $($client.name) requires five local screenshot patterns"
  $stages = [Collections.Generic.List[string]]::new()
  foreach ($pattern in $clientPatterns) {
    $relative = [IO.Path]::GetRelativePath($root, $pattern)
    $leaf = [IO.Path]::GetFileName($pattern)
    $name = [regex]::Match($leaf, '^(availability|initial|settled|rejoin|restart)-[*][.]png$')
    Assert-Session ($name.Success -and $relative -ceq $leaf) "screenshot pattern differs for $($client.name)"
    $null = $stages.Add($name.Groups[1].Value)
    $parent = [IO.Path]::GetDirectoryName($pattern)
    if (Test-Path -LiteralPath $parent -PathType Container) {
      Assert-Session (@(Get-ChildItem -LiteralPath $parent -File | Where-Object { $_.Name -like $leaf }).Count -eq 0) "fresh screenshot output already exists: $pattern"
    }
    $screenshotPatterns.Add([pscustomobject]@{client=$client.name;stage=$name.Groups[1].Value;path=$pattern;leaf=$leaf})
  }
  Assert-Session ((@($stages | Sort-Object) -join ',') -ceq 'availability,initial,rejoin,restart,settled') "client $($client.name) screenshot stages differ"
 }
 Assert-Session ($screenshotPatterns.Count -eq 10) 'screenshot patterns do not map exactly to the two clients'
} elseif($fixtureCase-ceq'library-paired-browser') {
  Assert-Session ($patterns.Count -eq 8 -and (@($patterns | Select-Object -Unique)).Count -eq 8) 'paired Browser session requires eight distinct screenshot patterns'
  foreach ($client in $clients) {
    $root = [IO.Path]::GetFullPath((Join-Path $client.write_data 'script-output/mir5-library-paired-browser'))
    $clientPatterns = @($patterns | Where-Object { Test-Within $root $_ })
    Assert-Session ($clientPatterns.Count -eq 4) "client $($client.name) requires four local paired Browser screenshot patterns"
    $stages = [Collections.Generic.List[string]]::new()
    foreach ($pattern in $clientPatterns) {
      $relative = [IO.Path]::GetRelativePath($root, $pattern)
      $leaf = [IO.Path]::GetFileName($pattern)
      $name = [regex]::Match($leaf, '^(first-open|search|refresh|reopen)-[*][.]png$')
      Assert-Session ($name.Success -and $relative -ceq $leaf) "paired Browser screenshot pattern differs for $($client.name)"
      $null = $stages.Add($name.Groups[1].Value)
      $parent = [IO.Path]::GetDirectoryName($pattern)
      if(Test-Path -LiteralPath $parent -PathType Container){Assert-Session (@(Get-ChildItem -LiteralPath $parent -File | Where-Object { $_.Name -like $leaf }).Count -eq 0) "fresh paired Browser screenshot output already exists: $pattern"}
      $screenshotPatterns.Add([pscustomobject]@{client=$client.name;stage=$name.Groups[1].Value;path=$pattern;leaf=$leaf})
    }
    Assert-Session ((@($stages | Sort-Object) -join ',') -ceq 'first-open,refresh,reopen,search') "client $($client.name) paired Browser screenshot stages differ"
  }
  Assert-Session ($screenshotPatterns.Count -eq 8) 'paired Browser screenshot patterns do not map exactly to two clients'
} else {
 Assert-Session ($patterns.Count-eq0) 'scripted-effects gameplay case must not claim Library screenshots'
}
foreach ($output in @($restartSave,$finalSave,$sessionPath)) { Assert-Session (-not (Test-Path -LiteralPath $output)) "fresh output already exists: $output" }

$processMemorySampler = $null
$processMemoryObservationPath = $null
if ($collectProcessMemoryObservations) {
  $processMemoryObservationPath = Resolve-BuildOutput (Join-Path $workroot 'process-memory-observations.json') 'process memory observations'
  Assert-Session (-not (Test-Path -LiteralPath $processMemoryObservationPath)) 'fresh process memory observation output already exists'
  $slots = foreach ($phase in $(if($fixtureCase -ceq 'library-paired-browser'){@('initial','restart')}else{@('initial','rejoin','restart')})) {
    foreach ($role in @('server', 'client-en', 'client-de')) {
      [pscustomobject]@{ phase=$phase; role=$role }
    }
  }
  $processMemorySampler = New-MIROwnedProcessMemorySampler -ExpectedSlots @($slots)
}
$records = [Collections.Generic.List[object]]::new()
$liveLogs = @((Join-Path $serverWriteData 'factorio-current.log')) + @($clients | ForEach-Object { Join-Path $_.write_data 'factorio-current.log' })
$deadline = [DateTime]::UtcNow.AddSeconds(900)
$server = $null; $activeClients = @()
$baseServer = @('--config',$serverConfig,'--mod-directory',$library,'--disable-audio','--no-log-rotation','--rcon-bind',('127.0.0.1:' + [string]$rconPort),'--rcon-password',$rconPassword)
function Start-Server([string]$Name, [string]$Save) {
  Start-Native $Name ($baseServer + @('--start-server',$Save,'--server-settings',$serverSettings,'--bind','127.0.0.1','--port',[string]$serverPort))
}
function Start-Clients([string]$Phase) {
  $expectedJoin=switch -CaseSensitive ($Phase){initial{1};rejoin{2};restart{3};default{throw 'unknown client phase'}}
  $started=[Collections.Generic.List[object]]::new()
  foreach($client in $clients){
    $actor=Start-Native ("client-$Phase-$($client.locale)") (@('--config',$client.config,'--mod-directory',$library,'--disable-audio','--no-log-rotation','--window-size','1280x720','--mp-connect',('127.0.0.1:'+ $serverPort),'--port',[string]$client.port)+$clientGraphics)
    $started.Add($actor)
    # Each native startup writes the shared library's settings cache. Wait
    # until the first real join proves those startup writes finished before
    # starting another client; archive/settings custody stays one exclusive job.
    $joined='\['+[regex]::Escape($markerPrefix)+'_JOIN\] '+[regex]::Escape([string]$client.name)+' '+$expectedJoin+'(?:\r?\n|$)'
    [void](Wait-For ("native join of "+$client.name) {
      return [regex]::IsMatch((Read-LogText (Join-Path $serverWriteData 'factorio-current.log')),$joined)
    })
    # The paired fixture counts all joins; the functional fixtures count per player.
    if($fixtureCase -ceq 'library-paired-browser'){$expectedJoin++}
  }
  $started.ToArray()
}

$sessionFailure = $null
$result = $null
try {
  if ($fixtureCase -ceq 'library-paired-browser') {
    $server = Start-Server 'server-initial' $seed
    [void](Wait-For 'paired Browser ready marker' { param($ignored) Get-PairedBrowserStageMarker (Read-LogText (Join-Path $serverWriteData 'factorio-current.log')) 'ready' $pairedArm })
    $activeClients = Start-Clients 'initial'
    foreach ($stage in @('first-open','search','refresh')) {
      [void](Wait-For ("paired Browser $stage marker") { param($ignored) Get-PairedBrowserStageMarker (Read-LogText (Join-Path $serverWriteData 'factorio-current.log')) $stage $pairedArm })
    }
    [void](Wait-For 'paired Browser initial client screenshots' { Find-Screenshots @('first-open','search','refresh') })
    [void](Wait-For 'paired Browser restart-ready marker' { param($ignored) Get-PairedBrowserStageMarker (Read-LogText (Join-Path $serverWriteData 'factorio-current.log')) 'restart-ready' $pairedArm })
    [void](Wait-For 'paired Browser restart save' { if (Test-SaveReady $restartSave) { return $true }; return $false })
    $restartHash = Get-SessionHash $restartSave
    Assert-Session ((Get-SessionHash $seed) -ceq $seedHash) 'initial server changed protected seed save'
    foreach ($client in $activeClients) { Stop-Record $client }
    $activeClients = @()
    Stop-Record $server
    $server = $null
    $initialServerLog = Save-PairedBrowserServerPhaseLog (Join-Path $serverWriteData 'factorio-current.log') 'initial'
    $initialText = Read-LogText $initialServerLog
    foreach ($stage in @('ready','first-open','search','refresh','restart-ready')) {
      $phaseMarker = Get-PairedBrowserStageMarker $initialText $stage $pairedArm
      Assert-Session ($null -ne $phaseMarker) "paired Browser initial phase log lacks $stage stage"
    }
    $initialProfiler = Get-PairedBrowserProfilerMarkers $initialText @('first_open','search','refresh')
    Assert-Session ((Get-SessionHash $restartSave) -ceq $restartHash -and (Get-SessionHash $seed) -ceq $seedHash) 'protected restart or seed save changed before host reload'
    $beforeRestartServerLog = $initialText
    $server = Start-Server 'server-restart' $restartSave
    [void](Wait-For 'paired Browser restarted server listener log' {
      $current = Read-LogText (Join-Path $serverWriteData 'factorio-current.log')
      if ($current -ceq $beforeRestartServerLog) { return $false }
      $delta = if ($current.StartsWith($beforeRestartServerLog, [StringComparison]::Ordinal)) { $current.Substring($beforeRestartServerLog.Length) } else { $current }
      return [regex]::IsMatch($delta, '(?im)Hosting game at|Starting server')
    })
    $activeClients = Start-Clients 'restart'
    [void](Wait-For 'paired Browser reopen marker' { param($ignored) Get-PairedBrowserStageMarker (Read-LogText (Join-Path $serverWriteData 'factorio-current.log')) 'reopen' $pairedArm })
    $completed = Wait-For 'paired Browser completed marker' { param($ignored) Get-PairedBrowserStageMarker (Read-LogText (Join-Path $serverWriteData 'factorio-current.log')) 'completed' $pairedArm }
    $captures = Wait-For 'paired Browser final save and client screenshots' {
      $screens = Find-Screenshots @('first-open','search','refresh','reopen')
      if ((Test-SaveReady $finalSave) -and $null -ne $screens) { return $screens }
      return $false
    }
    $screenshots = @($captures.files)
    Assert-Session ($screenshots.Count -eq 8) 'paired Browser final screenshot inventory differs'
    foreach ($client in $activeClients) { Stop-Record $client }
    $activeClients = @()
    Stop-Record $server
    $server = $null
    $restartServerLog = Save-PairedBrowserServerPhaseLog (Join-Path $serverWriteData 'factorio-current.log') 'restart' $initialServerLog
    $restartText = Read-LogText $restartServerLog
    foreach ($stage in @('reopen','completed')) {
      $phaseMarker = Get-PairedBrowserStageMarker $restartText $stage $pairedArm
      Assert-Session ($null -ne $phaseMarker) "paired Browser restart phase log lacks $stage stage"
    }
    $restartProfiler = Get-PairedBrowserProfilerMarkers $restartText @('reopen')
    $result = [ordered]@{
      schema=1;kind='MIR5LibraryPairedBrowserSessionV1';case=$fixtureCase;status='passed-private-two-client-session';paired_arm=$pairedArm
      engine_sha256=(Get-SessionHash $engine);seed_sha256=$seedHash;restart_save_sha256=$restartHash;final_save_sha256=(Get-SessionHash $finalSave)
      markers=@('ready','first-open','search','refresh','restart-ready','reopen','completed')
      profiler_observations=@(
        [ordered]@{phase='initial';role='server';log_path=$initialServerLog;log_sha256=(Get-SessionHash $initialServerLog);markers=@($initialProfiler)}
        [ordered]@{phase='restart';role='server';log_path=$restartServerLog;log_sha256=(Get-SessionHash $restartServerLog);markers=@($restartProfiler)}
      )
      clients=@($clients | ForEach-Object {[ordered]@{name=$_.name;locale=$_.locale;port=$_.port;config=$_.config;write_data=$_.write_data}})
      client_graphics_arguments=$clientGraphics
      screenshots=@($screenshots | ForEach-Object {[ordered]@{path=$_;sha256=(Get-SessionHash $_);width=1280;height=720}})
    }
  } else {

    $server = Start-Server 'server-initial' $seed
    [void](Wait-For 'ready marker' { param($ignored) Get-StageMarker (Read-LogText (Join-Path $serverWriteData 'factorio-current.log')) 'ready' 0 })
    $activeClients = Start-Clients 'initial'
    [void](Wait-For 'rejoin-ready marker' { param($ignored) Get-StageMarker (Read-LogText (Join-Path $serverWriteData 'factorio-current.log')) 'rejoin-ready' 2 })
    if($fixtureCase-ceq'library-multiplayer') {
      [void](Wait-For 'complete Availability client screenshots' { Find-Screenshots @('availability') })
      [void](Wait-For 'complete initial client screenshots' { Find-Screenshots @('initial') })
      [void](Wait-For 'complete settled client screenshots' { Find-Screenshots @('settled') })
    }
    # Stop our clients before clearing their server peers. A live kicked client
    # logs the expected disconnect as an engine Error, which must not be confused
    # with a product failure or hidden by weakening native fatal checks.
    foreach ($client in $activeClients) { Stop-Record $client }
    Invoke-LoopbackRconKicks $rconPort $rconPassword
    if ($null -ne $processMemorySampler) {
      Close-ProcessMemoryObservation $server
      $registration = Register-MIROwnedProcessMemoryProcess -Sampler $processMemorySampler -Phase 'rejoin' -Role 'server' -Process $server.process
      $server | Add-Member -NotePropertyName memory_observation -NotePropertyValue $registration -Force
    }
    $activeClients = Start-Clients 'rejoin'
    [void](Wait-For 'restart-ready marker' { param($ignored) Get-StageMarker (Read-LogText (Join-Path $serverWriteData 'factorio-current.log')) 'restart-ready' 4 })
    if($fixtureCase-ceq'library-multiplayer'){[void](Wait-For 'complete rejoin client screenshots' { Find-Screenshots @('rejoin') })}
    [void](Wait-For 'complete restart save' { if (Test-SaveReady $restartSave) { return $true }; return $false })
    $restartHash = Get-SessionHash $restartSave
    Assert-Session ((Get-SessionHash $seed) -ceq $seedHash) 'initial server changed protected seed save'
    foreach ($client in $activeClients) { Stop-Record $client }; $activeClients = @()
    Stop-Record $server; $server = $null
    Assert-Session ((Get-SessionHash $restartSave) -ceq $restartHash -and (Get-SessionHash $seed) -ceq $seedHash) 'protected restart or seed save changed before host reload'
    $beforeRestartServerLog = Read-LogText (Join-Path $serverWriteData 'factorio-current.log')
    $server = Start-Server 'server-restart' $restartSave
    [void](Wait-For 'restarted server listener log' {
      $current = Read-LogText (Join-Path $serverWriteData 'factorio-current.log')
      if ($current -ceq $beforeRestartServerLog) { return $false }
      $delta = if ($current.StartsWith($beforeRestartServerLog, [StringComparison]::Ordinal)) { $current.Substring($beforeRestartServerLog.Length) } else { $current }
      return [regex]::IsMatch($delta, '(?im)Hosting game at|Starting server')
    })
    $activeClients = Start-Clients 'restart'
    $completed = Wait-For 'completed marker' { param($ignored) Get-StageMarker (Read-LogText (Join-Path $serverWriteData 'factorio-current.log')) 'completed' 6 }
    Assert-Session ($completed.witnesses.host_restart_observed -eq $true -and $completed.witnesses.on_load_read_only -eq $true) 'completed witness lacks host-reload evidence'
    if($fixtureCase-ceq'library-multiplayer') {
      Assert-Session ($completed.witnesses.availability_terminal_labels_checked -eq $true -and $completed.witnesses.screenshot_calls -eq 10) 'completed witness lacks Availability evidence'
    }
    $captures = Wait-For 'complete final save and client screenshots' {
      $screens = if($fixtureCase-ceq'library-multiplayer'){Find-Screenshots @('availability','initial','settled','rejoin','restart')}else{[pscustomobject]@{files=@()}}
      if ((Test-SaveReady $finalSave) -and $null -ne $screens) { return $screens }; return $false
    }
    $screenshots = @($captures.files)
    if ($fixtureCase -ceq 'library-multiplayer') {
      Assert-Session ($screenshots.Count -eq 10) 'final screenshot inventory differs'
    }
    $result = [ordered]@{
      schema=1;kind=$(if($fixtureCase-ceq'library-multiplayer'){'MIR5LibraryMultiplayerSessionV1'}else{'MIR5ScriptedEffectsMultiplayerSessionV1'});case=$fixtureCase;status='passed-private-two-client-session'
      engine_sha256=(Get-SessionHash $engine); seed_sha256=$seedHash; restart_save_sha256=$restartHash
      final_save_sha256=(Get-SessionHash $finalSave); markers=@('ready','rejoin-ready','restart-ready','completed')
      clients=@($clients | ForEach-Object {[ordered]@{name=$_.name;locale=$_.locale;port=$_.port;config=$_.config;write_data=$_.write_data}})
      client_graphics_arguments=$clientGraphics
      screenshots=@($screenshots | ForEach-Object {[ordered]@{path=$_;sha256=(Get-SessionHash $_);width=1280;height=720}})
    }
  }
}
catch { $sessionFailure = $_ }
finally {
  # Stop clients before their server, as in the explicit phase transitions.
  # Continue closing other owned processes if one reports a late failure.
  $closing = @($records)
  [Array]::Reverse($closing)
  foreach ($record in $closing) {
    if (-not $record.closed) {
      try { Stop-Record $record }
      catch {
        if ($null -eq $sessionFailure) { $sessionFailure = $_ }
        Write-Warning "could not clean owned $($record.name): $($_.Exception.Message)"
      }
    }
  }
  $sampler = Get-Variable -Name processMemorySampler -ValueOnly -ErrorAction SilentlyContinue
  if ($null -ne $sampler) {
    if ($null -ne $sessionFailure) {
      Set-MIROwnedProcessMemoryIncomplete -Sampler $sampler -Reason 'native-session-failure'
    }
    $memorySummary = $null
    try {
      $receipt = Write-MIROwnedProcessMemoryObservationReceipt -Sampler $sampler -Path $processMemoryObservationPath
      $memorySummary = [ordered]@{
        status = [string]$receipt.status
        performance_acceptance = $false
        artifact = [ordered]@{
          leaf = [IO.Path]::GetFileName($processMemoryObservationPath)
          sha256 = Get-SessionHash $processMemoryObservationPath
          bytes = [int64](Get-Item -LiteralPath $processMemoryObservationPath).Length
        }
      }
    }
    catch {
      $memorySummary = [ordered]@{
        status = 'incomplete-observation'
        performance_acceptance = $false
        failure = 'memory-receipt-write-failure'
      }
    }
    if ($null -ne $result) {
      $result.process_memory_observations = $memorySummary
    }
  }
}
if ($null -ne $sessionFailure) { throw $sessionFailure }
# A passing receipt includes successful process shutdown and log draining.
[IO.File]::WriteAllText($sessionPath, ($result | ConvertTo-Json -Depth 10) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
$result
