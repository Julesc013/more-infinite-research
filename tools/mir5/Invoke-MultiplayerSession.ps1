# Child process orchestrator for the private F200 Library multiplayer fixture.
# It runs only under the governed native-probe parent. The parent prepares and
# validates the selected library, configs, and player-data files before calling
# this script. Spec fields: engine, engine_sha256, archive_library, workroot,
# seed_save, seed_sha256, server_config, server_settings, server_write_data,
# port, rcon_port, rcon_password, clients, expected_screenshots. Screenshot
# entries are absolute client write-data patterns: initial/rejoin/restart-*.png
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

function Assert-Session([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "[mir5-multiplayer-session] $Message" }
}
function Get-SessionHash([string]$Path) {
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
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
function Complete-Record($Record) {
  if ($Record.closed) { return }
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
  Assert-NoFatal (Read-LiveText) 'live native logs'
}
function Get-StageMarker([string]$Text, [string]$Stage, [int]$ExpectedJoins) {
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($match in [regex]::Matches($Text, '\[MIR5_LIBRARY_MULTIPLAYER\] RESULT (\{[^\r\n]+\})')) {
    try { $row = $match.Groups[1].Value | ConvertFrom-Json }
    catch { continue } # A FileShare.ReadWrite read can end during an appended marker.
    if ($row.case -ceq 'library-multiplayer' -and $row.stage -ceq $Stage) { $rows.Add($row) }
  }
  if ($rows.Count -eq 0) { return $null }
  Assert-Session ($rows.Count -eq 1 -and $rows[0].status -ceq 'passed') "stage witness differs: $Stage"
  $witness = $rows[0].witnesses
  Assert-Session ($witness.actual_join_events -eq $ExpectedJoins) "$Stage witness join count differs"
  Assert-Session ($witness.two_connected_clients_required -eq $true -and $witness.distinct_personal_query_and_selection -eq $true -and $witness.native_research_queue_and_effects_unchanged -eq $true) "$Stage witness lacks native two-client checks"
  return $rows[0]
}
function Wait-For([string]$Description, [scriptblock]$Predicate) {
  while ([DateTime]::UtcNow -lt $deadline) {
    Assert-Active
    $value = & $Predicate (Read-LiveText)
    if ($null -ne $value -and $value -ne $false) { return $value }
    Start-Sleep -Milliseconds 200
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
    $match = [regex]::Match($matches[0].Name, '^(initial|rejoin|restart)-([12])[.]png$')
    Assert-Session $match.Success 'captured screenshot filename differs'
    if ($indices.ContainsKey($expected.client) -and $indices[$expected.client] -ne $match.Groups[2].Value) {
      throw "screenshot player index changed for $($expected.client)"
    }
    $indices[$expected.client] = $match.Groups[2].Value
    $files.Add($path)
  }
  if ($Stages.Count -eq 3) {
    Assert-Session ($indices.Count -eq 2 -and (@($indices.Values | Select-Object -Unique)).Count -eq 2) 'client screenshot player indexes are not distinct and stable'
  }
  return [pscustomobject]@{files=@($files);indexes=$indices}
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
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
Assert-Session ([int]$spec.port -eq 34198) 'server port must be loopback 34198'
$rconPort = [int]$spec.rcon_port
Assert-Session ($rconPort -eq 34201) 'RCON port must be loopback 34201'
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
  Assert-Session ([int]$client.port -in @(34199,34200) -and -not $ports.Contains([int]$client.port)) 'client ports must be distinct 34199/34200'
  $null = $ports.Add([int]$client.port)
}
Assert-Session (($clients.locale | Sort-Object) -join ',' -ceq 'de,en') 'two client locales must be en and de'
Assert-Session ((@($names | Sort-Object) -join ',') -ceq 'MIR5Deutsch,MIR5English') 'two client identities must be MIR5English and MIR5Deutsch'
$restartSave = Resolve-BuildOutput (Join-Path $serverWriteData 'saves/mir5-library-multiplayer-restart.zip') 'restart save'
$finalSave = Resolve-BuildOutput (Join-Path $serverWriteData 'saves/mir5-native-complete.zip') 'final save'
$sessionPath = Resolve-BuildOutput (Join-Path $workroot 'session.json') 'session output'
$screenshotPatterns = [Collections.Generic.List[object]]::new()
$patterns = @($spec.expected_screenshots | ForEach-Object { Resolve-BuildOutput ([string]$_) 'expected screenshot pattern' })
Assert-Session ($patterns.Count -eq 6 -and (@($patterns | Select-Object -Unique)).Count -eq 6) 'session requires six distinct screenshot patterns'
foreach ($client in $clients) {
  $root = [IO.Path]::GetFullPath((Join-Path $client.write_data 'script-output/mir5-library-multiplayer'))
  $clientPatterns = @($patterns | Where-Object { Test-Within $root $_ })
  Assert-Session ($clientPatterns.Count -eq 3) "client $($client.name) requires three local screenshot patterns"
  $stages = [Collections.Generic.List[string]]::new()
  foreach ($pattern in $clientPatterns) {
    $relative = [IO.Path]::GetRelativePath($root, $pattern)
    $leaf = [IO.Path]::GetFileName($pattern)
    $name = [regex]::Match($leaf, '^(initial|rejoin|restart)-[*][.]png$')
    Assert-Session ($name.Success -and $relative -ceq $leaf) "screenshot pattern differs for $($client.name)"
    $null = $stages.Add($name.Groups[1].Value)
    $parent = [IO.Path]::GetDirectoryName($pattern)
    if (Test-Path -LiteralPath $parent -PathType Container) {
      Assert-Session (@(Get-ChildItem -LiteralPath $parent -File | Where-Object { $_.Name -like $leaf }).Count -eq 0) "fresh screenshot output already exists: $pattern"
    }
    $screenshotPatterns.Add([pscustomobject]@{client=$client.name;stage=$name.Groups[1].Value;path=$pattern;leaf=$leaf})
  }
  Assert-Session ((@($stages | Sort-Object) -join ',') -ceq 'initial,rejoin,restart') "client $($client.name) screenshot stages differ"
}
Assert-Session ($screenshotPatterns.Count -eq 6) 'screenshot patterns do not map exactly to the two clients'
foreach ($output in @($restartSave,$finalSave,$sessionPath)) { Assert-Session (-not (Test-Path -LiteralPath $output)) "fresh output already exists: $output" }

$records = [Collections.Generic.List[object]]::new()
$liveLogs = @((Join-Path $serverWriteData 'factorio-current.log')) + @($clients | ForEach-Object { Join-Path $_.write_data 'factorio-current.log' })
$deadline = [DateTime]::UtcNow.AddSeconds(900)
$server = $null; $activeClients = @()
$baseServer = @('--config',$serverConfig,'--mod-directory',$library,'--disable-audio','--no-log-rotation','--rcon-bind',('127.0.0.1:' + [string]$rconPort),'--rcon-password',$rconPassword)
function Start-Server([string]$Name, [string]$Save) {
  Start-Native $Name ($baseServer + @('--start-server',$Save,'--server-settings',$serverSettings,'--bind','127.0.0.1','--port','34198'))
}
function Start-Clients([string]$Phase) {
  @($clients | ForEach-Object {
    Start-Native ("client-$Phase-$($_.locale)") @('--config',$_.config,'--mod-directory',$library,'--disable-audio','--no-log-rotation','--mp-connect','127.0.0.1:34198','--port',[string]$_.port)
  })
}

try {
  $server = Start-Server 'server-initial' $seed
  [void](Wait-For 'ready marker' { param($ignored) Get-StageMarker (Read-LogText (Join-Path $serverWriteData 'factorio-current.log')) 'ready' 0 })
  $activeClients = Start-Clients 'initial'
  [void](Wait-For 'rejoin-ready marker' { param($ignored) Get-StageMarker (Read-LogText (Join-Path $serverWriteData 'factorio-current.log')) 'rejoin-ready' 2 })
  [void](Wait-For 'complete initial client screenshots' { Find-Screenshots @('initial') })
  Invoke-LoopbackRconKicks $rconPort $rconPassword
  foreach ($client in $activeClients) { Stop-Record $client }; $activeClients = Start-Clients 'rejoin'
  [void](Wait-For 'restart-ready marker' { param($ignored) Get-StageMarker (Read-LogText (Join-Path $serverWriteData 'factorio-current.log')) 'restart-ready' 4 })
  [void](Wait-For 'complete rejoin client screenshots' { Find-Screenshots @('rejoin') })
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
  Assert-Session ($completed.witnesses.host_restart_observed -eq $true -and $completed.witnesses.on_load_read_only -eq $true -and $completed.witnesses.screenshot_calls -eq 6) 'completed witness lacks host-reload evidence'
  $captures = Wait-For 'complete final save and client screenshots' {
    $screens = Find-Screenshots @('initial','rejoin','restart')
    if ((Test-SaveReady $finalSave) -and $null -ne $screens) { return $screens }; return $false
  }
  $screenshots = @($captures.files)
  $result = [ordered]@{
    schema=1; kind='MIR5LibraryMultiplayerSessionV1'; status='passed-private-two-client-session'
    engine_sha256=(Get-SessionHash $engine); seed_sha256=$seedHash; restart_save_sha256=$restartHash
    final_save_sha256=(Get-SessionHash $finalSave); markers=@('ready','rejoin-ready','restart-ready','completed')
    clients=@($clients | ForEach-Object {[ordered]@{name=$_.name;locale=$_.locale;port=$_.port;config=$_.config;write_data=$_.write_data}})
    screenshots=@($screenshots | ForEach-Object {[ordered]@{path=$_;sha256=(Get-SessionHash $_);width=1280;height=720}})
  }
  [IO.File]::WriteAllText($sessionPath, ($result | ConvertTo-Json -Depth 10) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
  $result
}
finally {
  foreach ($record in @($records)) {
    if (-not $record.closed) {
      try { Stop-Record $record } catch { Write-Warning "could not clean owned $($record.name): $($_.Exception.Message)" }
    }
  }
}
