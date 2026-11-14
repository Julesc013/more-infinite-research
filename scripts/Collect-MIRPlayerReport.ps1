param(
  [string]$FactorioUserData = '',
  [string]$OutputDirectory = '',
  [switch]$IncludeModSettings,
  [string]$SavePath = '',
  [ValidateRange(1, 4096)][int]$MaxSaveMiB = 1024,
  [switch]$CopyPath,
  [switch]$ShowInExplorer
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($FactorioUserData)) {
  if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
    throw 'Set -FactorioUserData to the directory containing Factorio logs and mods.'
  }
  $FactorioUserData = Join-Path $env:APPDATA 'Factorio'
}
$userData = (Resolve-Path -LiteralPath $FactorioUserData -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $userData -PathType Container)) {
  throw "Factorio user-data directory is missing: $userData"
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = (Get-Location).Path
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$outputRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path

Add-Type -AssemblyName System.IO.Compression
$utf8 = [Text.UTF8Encoding]::new($false)
$maxLogBytes = 8MB
$maxModListBytes = 2MB
$maxSettingsBytes = 16MB

function Read-MIRFileRange {
  param([IO.FileStream]$Stream, [long]$Offset, [int]$Length)
  [void]$Stream.Seek($Offset, [IO.SeekOrigin]::Begin)
  $buffer = New-Object byte[] $Length
  $received = 0
  while ($received -lt $Length) {
    $count = $Stream.Read($buffer, $received, $Length - $received)
    if ($count -eq 0) { throw 'The source changed during capture.' }
    $received += $count
  }
  return ,$buffer
}

function Read-MIRBoundedFile {
  param([string]$Path, [int]$Limit, [switch]$HeadAndTail)
  $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
  try {
    $size = $stream.Length
    $ranges = @()
    if ($size -gt $Limit) {
      if (-not $HeadAndTail) { return [pscustomobject]@{ text = $null; bytes = $size; truncated = $true } }
      $half = [int]($Limit / 2)
      $head = Read-MIRFileRange -Stream $stream -Offset 0 -Length $half
      $tailOffset = $size - $half
      $tail = Read-MIRFileRange -Stream $stream -Offset $tailOffset -Length $half
      # Retain complete lines at both cut points; ranges refer to source bytes,
      # before UTF-8 decoding and text redaction, with an exclusive end offset.
      $headLength = [Array]::LastIndexOf($head, [byte]10) + 1
      $tailSkip = [Array]::IndexOf($tail, [byte]10) + 1
      if ($tailSkip -eq 0) { $tailSkip = $tail.Length }
      $tailLength = $tail.Length - $tailSkip
      $ranges = @(@{start = 0; end = $headLength}, @{start = $tailOffset + $tailSkip; end = $size})
      $omitted = $size - $headLength - $tailLength
      $content = $utf8.GetString($head, 0, $headLength) +
        "`n[MIR collector omitted $omitted source bytes between the header and tail.]`n" +
        $utf8.GetString($tail, $tailSkip, $tailLength)
    } else {
      $buffer = Read-MIRFileRange -Stream $stream -Offset 0 -Length ([int]$size)
      $content = $utf8.GetString($buffer)
      $ranges = @(@{start = 0; end = $size})
    }
    return [pscustomobject]@{
      text = $content; bytes = $size; truncated = $size -gt $Limit
      ranges = $ranges; length_changed = $stream.Length -ne $size
    }
  } finally { $stream.Dispose() }
}

function Get-MIRTextHash {
  param([string]$Value)
  $algorithm = [Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($algorithm.ComputeHash($utf8.GetBytes($Value))).Replace('-', '') }
  finally { $algorithm.Dispose() }
}

function Protect-MIRLogText {
  param([string]$Value)
  $protected = $Value
  foreach ($privatePath in @($env:USERPROFILE, $env:APPDATA, $userData)) {
    if (-not [string]::IsNullOrWhiteSpace($privatePath)) {
      $protected = [regex]::Replace($protected, [regex]::Escape($privatePath), '<FACTORIO_USER_PATH>', 'IgnoreCase')
      $protected = [regex]::Replace($protected, [regex]::Escape($privatePath.Replace('\', '/')), '<FACTORIO_USER_PATH>', 'IgnoreCase')
    }
  }
  $protected = [regex]::Replace($protected, '(?i)\b[A-Z]:[\\/](?:Users|Documents and Settings)[\\/][^\\/\s]+', '<USER_PROFILE>')
  $protected = [regex]::Replace($protected, '(?i)/(?:home|Users)/[^/\s]+', '<USER_PROFILE>')
  # Keep this standalone Windows PowerShell entry point self-contained. The
  # quoted-value grammar follows the developer support-export consumer;
  # suffix keys retain the collector's existing unquoted redaction behavior.
  $credentialPattern = '(?i)(?<prefix>(?:access[_-]?token|token|secret|password|api[_-]?key)["'']?\s*[=:]\s*)(?<value>"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|[^\s,;]+)'
  $protected = [regex]::Replace($protected, $credentialPattern, [Text.RegularExpressions.MatchEvaluator]{
    param($match)
    $value = $match.Groups['value'].Value
    $replacement = '<REDACTED>'
    if ($value.Length -ge 2 -and ($value[0] -ceq [char]34 -or $value[0] -ceq [char]39) -and $value[0] -ceq $value[$value.Length - 1]) {
      $replacement = [string]$value[0] + '<REDACTED>' + [string]$value[0]
    }
    return $match.Groups['prefix'].Value + $replacement
  }, [Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(2))
  $protected = [regex]::Replace($protected, '(?i)\b((?:proxy-)?authorization)\s*:\s*(bearer|basic)\s+[^\s,;]+', '$1: $2 <REDACTED>')
  $protected = [regex]::Replace($protected, '(?i)\bbearer\s+[^\s,;]+', 'Bearer <REDACTED>')
  $protected = [regex]::Replace($protected, '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,63}\b', '<EMAIL_REDACTED>')
  return $protected
}

function Add-MIRZipText {
  param([IO.Compression.ZipArchive]$Archive, [string]$Name, [string]$Value)
  $entry = $Archive.CreateEntry($Name, [IO.Compression.CompressionLevel]::Optimal)
  $writer = [IO.StreamWriter]::new($entry.Open(), $utf8)
  try { $writer.Write($Value) } finally { $writer.Dispose() }
}

function Add-MIRTextCapture {
  param([IO.Compression.ZipArchive]$Archive, [string]$Path, [string]$Name,
    [int]$Limit, [switch]$HeadAndTail, [switch]$OpaqueProfile)
  $row = [ordered]@{name = $Name; status = 'missing'; included = $false}
  try {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $row }
    $row.source_modified_utc = (Get-Item -LiteralPath $Path).LastWriteTimeUtc.ToString('o')
    $read = Read-MIRBoundedFile -Path $Path -Limit $Limit -HeadAndTail:$HeadAndTail
    $row.source_bytes = $read.bytes
    if ($null -eq $read.text) { $row.status = 'omitted-size'; $row.limit_bytes = $Limit; return $row }
    $safe = Protect-MIRLogText -Value $read.text
    $row.status = 'captured'
    if ($read.truncated) { $row.status = 'truncated' }
    $row.source_byte_ranges = $read.ranges
    $row.source_length_changed_during_capture = $read.length_changed
    $row.tail_truncated = $read.truncated
    $row.redacted = $safe -cne $read.text
    $row.redaction = 'known text patterns only; review before sharing'
    if ($OpaqueProfile) { $row.redaction = 'encoded profile content is not decoded or inspected; may contain player metadata' }
    $row.captured_bytes = $utf8.GetByteCount($safe)
    $row.captured_sha256 = Get-MIRTextHash -Value $safe
    Add-MIRZipText -Archive $Archive -Name $Name -Value $safe
    $row.included = $true
    if ($Name -eq 'logs/factorio-current.log') {
      $row.observed_mod_versions = @()
      $row.mod_observations_truncated = $false
      $row.mod_observation_status = 'parsed-captured-ranges'
      $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
      $pattern = '(?m)^[ \t]*(?:\d+(?:\.\d+)?[ \t]+)?Loading mod (?<mod>[A-Za-z0-9_-]{1,256}) (?<version>\d{1,10}\.\d{1,10}\.\d{1,10})(?:[ \t\r\n]|$)'
      try {
        foreach ($match in [regex]::Matches($read.text, $pattern, [Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(2))) {
          $modName = $match.Groups['mod'].Value
          $version = $match.Groups['version'].Value
          if (-not $seen.Add($modName + '/' + $version)) { continue }
          if ($seen.Count -gt 4096) { $row.mod_observations_truncated = $true; break }
          $row.observed_mod_versions += [ordered]@{name = $modName; version = $version}
        }
      } catch {
        $row.mod_observation_status = 'incomplete-parser-limit'
        $row.mod_observations_truncated = $true
      }
    }
  } catch {
    $row.status = 'unreadable'
    $row.error = 'The file could not be captured. Its local path and exception details are excluded.'
  }
  return $row
}

function Add-MIRExactInput {
  param([IO.Compression.ZipArchive]$Archive, [string]$Path, [string]$Name,
    [long]$Limit, [switch]$Include, [switch]$HashWhenExcluded)
  $row = [ordered]@{name = $Name; status = 'not-selected'; selected = [bool]$Include; included = $false; bytes_read = 0L}
  if (-not $Include -and -not $HashWhenExcluded) { return $row }
  $inputStream = $null; $entryStream = $null; $algorithm = $null
  try {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { $row.status = 'missing'; return $row }
    $inputStream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $size = $inputStream.Length
    $row.source_bytes = $size
    if ($size -gt $Limit) { $row.status = 'omitted-size'; $row.limit_bytes = $Limit; return $row }
    $algorithm = [Security.Cryptography.SHA256]::Create()
    if ($Include) {
      $entry = $Archive.CreateEntry($Name, [IO.Compression.CompressionLevel]::Optimal)
      $entryStream = $entry.Open()
      $row.included = $true
    }
    $buffer = New-Object byte[] 65536
    $copied = 0L
    while ($copied -lt $size) {
      $count = $inputStream.Read($buffer, 0, [int][Math]::Min($buffer.Length, $size - $copied))
      if ($count -eq 0) { throw 'The selected input changed during capture.' }
      $row.bytes_read += $count
      if ($entryStream) { $entryStream.Write($buffer, 0, $count) }
      [void]$algorithm.TransformBlock($buffer, 0, $count, $buffer, 0)
      $copied += $count
    }
    if ($inputStream.Length -ne $size) { throw 'The selected input changed during capture.' }
    [void]$algorithm.TransformFinalBlock((New-Object byte[] 0), 0, 0)
    $row.sha256 = [BitConverter]::ToString($algorithm.Hash).Replace('-', '')
    if ($Include) {
      $row.status = 'captured'
      $row.captured_bytes = $copied
      $row.captured_sha256 = $row.sha256
      $row.redacted = $false
    } else { $row.status = 'hash-only' }
  } catch {
    $row.status = 'unreadable'
    if ($row.included) { $row.status = 'incomplete'; $row.captured_bytes = $copied }
    $row.error = 'The selected input could not be read completely; do not use an incomplete entry as a save or settings file.'
  } finally {
    if ($entryStream) { $entryStream.Dispose() }
    if ($algorithm) { $algorithm.Dispose() }
    if ($inputStream) { $inputStream.Dispose() }
  }
  return $row
}

$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$outputPath = Join-Path $outputRoot ("MIR-support-$stamp-$([guid]::NewGuid().ToString('N').Substring(0, 8)).zip")
$stream = [IO.File]::Open($outputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
$archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
try {
  $manifest = [ordered]@{
    schema = 1
    kind = 'MIRPlayerStartupReportV1'
    collected_utc = [DateTime]::UtcNow.ToString('o')
    source = 'Factorio user-data directory supplied locally; its path is excluded from this archive'
    logs = @()
    mod_list = $null
    mod_settings = $null
    save = $null
    runtime_exports = @()
    mir_archives = @()
    log_observed_archives = @()
    archive_identity_scope = 'Installed MIR ZIPs only. mod-list.json is not an exact-version lockfile; engine log versions describe that logged launch.'
    archive_identity_limits = @{max_files = 32; max_file_bytes = 128MB; max_total_bytes = 512MB}
    log_observed_archive_scope = 'Budget-limited identity evidence from ZIP filenames matching captured current-log Loading mod observations; no proof that an archive rather than an unpacked mod was selected. No dependency ZIP bytes are included.'
    log_observed_archive_limits = @{max_observations = 4096; max_file_bytes = 128MB; max_total_bytes = 1GB}
    input_consistency = 'Files are collected separately; this report does not certify an atomic snapshot of a running game.'
    contains_unredacted_inputs = $false
    requested_inputs_captured = $true
    notes = @()
  }
  foreach ($name in @('factorio-current.log', 'factorio-previous.log')) {
    $path = Join-Path $userData $name
    $manifest.logs += Add-MIRTextCapture -Archive $archive -Path $path -Name "logs/$name" -Limit $maxLogBytes -HeadAndTail
  }

  $modsDir = Join-Path $userData 'mods'
  $modListPath = Join-Path $modsDir 'mod-list.json'
  $manifest.mod_list = Add-MIRTextCapture -Archive $archive -Path $modListPath -Name 'mods/mod-list.json' -Limit $maxModListBytes
  $modSettingsPath = Join-Path $modsDir 'mod-settings.dat'
  $manifest.mod_settings = Add-MIRExactInput -Archive $archive -Path $modSettingsPath -Name 'mods/mod-settings.dat' -Limit $maxSettingsBytes -Include:$IncludeModSettings -HashWhenExcluded
  $manifest.save = Add-MIRExactInput -Archive $archive -Path $SavePath -Name 'inputs/save.zip' -Limit ([long]$MaxSaveMiB * 1MB) -Include:(-not [string]::IsNullOrWhiteSpace($SavePath))
  foreach ($inputRow in @($manifest.mod_settings, $manifest.save)) {
    if ($inputRow.included) { $manifest.contains_unredacted_inputs = $true }
    if ($inputRow.selected -and $inputRow.status -ne 'captured') { $manifest.requested_inputs_captured = $false }
  }
  foreach ($spec in @(
      @{path = 'script-output/more-infinite-research/mir.log'; limit = 65536; opaque = $false},
      @{path = 'script-output/more-infinite-research/settings/mir-settings-profile.txt'; limit = 2MB; opaque = $true})) {
    $exportRow = Add-MIRTextCapture -Archive $archive -Path (Join-Path $userData $spec.path) -Name $spec.path -Limit $spec.limit -OpaqueProfile:$spec.opaque
    $manifest.runtime_exports += $exportRow
    if ($spec.opaque -and $exportRow.included) { $manifest.contains_unredacted_inputs = $true }
  }
  $archiveHashBytes = 0L
  if ($manifest.logs[0].Contains('observed_mod_versions')) {
    foreach ($observed in $manifest.logs[0].observed_mod_versions) {
      $fileName = $observed.name + '_' + $observed.version + '.zip'
      $remaining = 1GB - $archiveHashBytes
      if ($remaining -le 0) {
        $identity = [ordered]@{name = $fileName; status = 'omitted-budget'; included = $false}
      } else {
        $identity = Add-MIRExactInput -Archive $archive -Path (Join-Path $modsDir $fileName) -Name $fileName -Limit ([Math]::Min(128MB, $remaining)) -HashWhenExcluded
        if ($identity.status -eq 'omitted-size' -and $remaining -lt 128MB -and $identity.source_bytes -le 128MB) { $identity.status = 'omitted-budget' }
        $archiveHashBytes += $identity.bytes_read
      }
      $identity.observed_mod_name = $observed.name
      $identity.observed_mod_version = $observed.version
      $identity.unpacked_candidate_present = (Test-Path -LiteralPath (Join-Path $modsDir ($observed.name + '_' + $observed.version)) -PathType Container) -or
        (Test-Path -LiteralPath (Join-Path $modsDir $observed.name) -PathType Container)
      $manifest.log_observed_archives += $identity
    }
  }
  $mirArchiveCount = 0
  $mirListOk = $true
  if (Test-Path -LiteralPath $modsDir -PathType Container) {
    try {
      $mirFiles = @(Get-ChildItem -LiteralPath $modsDir -File -Filter 'more-infinite-research_*.zip' | Sort-Object Name)
      $mirArchiveCount = $mirFiles.Count
      $mirHashBytes = 0L
      foreach ($file in @($mirFiles | Select-Object -First 32)) {
        try {
          $remaining = 512MB - $mirHashBytes
          if ($remaining -le 0) {
            $identity = [ordered]@{name = $file.Name; status = 'omitted-budget'; included = $false; bytes_read = 0L}
          } else {
            $identity = Add-MIRExactInput -Archive $archive -Path $file.FullName -Name $file.Name -Limit ([Math]::Min(128MB, $remaining)) -HashWhenExcluded
            if ($identity.Contains('source_bytes')) { $identity.bytes = $identity.source_bytes }
            if ($identity.status -eq 'omitted-size' -and $remaining -lt 128MB -and $identity.source_bytes -le 128MB) { $identity.status = 'omitted-budget' }
            $mirHashBytes += $identity.bytes_read
          }
          $manifest.mir_archives += $identity
        } catch {
          $manifest.notes += "$($file.Name) could not be hashed; its identity is unavailable."
        }
      }
      if ($mirFiles.Count -gt 32) { $manifest.notes += 'MIR archive identity inventory stopped after 32 files.' }
    } catch {
      $mirListOk = $false
      $manifest.notes += 'The mods directory could not be listed; installed MIR identities are unavailable.'
    }
  }
  if ($mirListOk -and $mirArchiveCount -eq 0) { $manifest.notes += 'No MIR ZIP was found in the selected mods directory.' }

  Add-MIRZipText -Archive $archive -Name 'README.txt' -Value @'
MIR startup support report

This archive works even when MIR or Factorio stops during startup. It contains
the available current and previous Factorio logs, the enabled mod list,
installed MIR package identities and existing MIR runtime exports. Long logs
retain complete lines from their first and last 4 MiB. The manifest records
the selected source byte ranges (zero-based, end-exclusive) and omissions.
Missing runtime exports are normal when startup fails before MIR can write them.
User paths, email
addresses, authorization headers and common quoted password/token assignments
are redacted from captured logs and mod-list text. The manifest hashes the
captured redacted bytes and records whether mod-list text changed.

MIRSET1 profiles can contain encoded player metadata/settings that this collector
does not decode or inspect. Text redaction is not a guarantee that all private
content has been removed. Existing exports can be older than the failing launch;
their recorded modification times do not prove that they describe that launch.

Raw mod-settings.dat is included ONLY with -IncludeModSettings (16 MiB maximum).
A save is included ONLY when selected with -SavePath, stored as inputs/save.zip.
The default save bound is 1024 MiB; -MaxSaveMiB selects 1 through 4096 MiB.
These optional raw inputs are NOT redacted and may contain private information.
Their hashes describe the captured bytes. Never use an entry marked incomplete.
The manifest states whether every explicitly requested input was captured.

No save is selected automatically. Automatic collection excludes crash dumps,
credentials files, full mod packages and unrelated personal files. Nothing is uploaded.
Review the archive and choose a private sharing route for sensitive inputs.
Files are captured separately, not as an atomic snapshot of a running game.
mod-list.json is not a version lockfile; retained log versions describe that log's
launch, and installed MIR ZIP identities alone do not prove the selected package.
The collector also hashes matching ZIP filenames for up to 4096 distinct current-log
mod/version observations, within 128 MiB per archive and 1 GiB total. This is
budget-limited identity evidence; log truncation or a failed load can leave mods
unobserved. Missing, oversized and unreadable matches are explicit. Metadata/parser
limits are recorded with the current log. Official built-in mods may have no
ZIP in this directory. Unpacked mods and edited or ambiguous selections remain
unverified; the filename association is not proof of the engine's selected bytes.
'@
  Add-MIRZipText -Archive $archive -Name 'manifest.json' -Value (($manifest | ConvertTo-Json -Depth 8) + "`n")
} finally {
  $archive.Dispose()
  $stream.Dispose()
}

Write-Output "MIR support report: $outputPath"
if (-not $manifest.requested_inputs_captured) {
  Write-Warning 'Some explicitly requested inputs were not captured. Review manifest.json before using this report for reproduction.'
}
if ($CopyPath) {
  try { Set-Clipboard -Value $outputPath; Write-Output 'Report path copied to clipboard.' }
  catch { Write-Output 'Clipboard unavailable; use the report path printed above.' }
}
if ($ShowInExplorer) {
  try {
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $outputPath) -WindowStyle Normal
  } catch {
    Write-Output 'Could not open the report folder; use the report path printed above.'
  }
}
