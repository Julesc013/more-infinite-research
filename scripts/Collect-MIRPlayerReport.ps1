param(
  [string]$FactorioUserData = '',
  [string]$OutputDirectory = '',
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

function Read-MIRBoundedFile {
  param([string]$Path, [long]$Limit, [switch]$Tail)
  $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
  try {
    $size = $stream.Length
    if ($size -gt $Limit) {
      if (-not $Tail) { return [pscustomobject]@{ text = $null; bytes = $size; truncated = $true } }
      [void]$stream.Seek(-$Limit, [IO.SeekOrigin]::End)
    }
    $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true)
    try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if ($size -gt $Limit) {
      $firstLine = $content.IndexOf("`n")
      if ($firstLine -ge 0) { $content = $content.Substring($firstLine + 1) }
    }
    return [pscustomobject]@{ text = $content; bytes = $size; truncated = $size -gt $Limit }
  } finally { $stream.Dispose() }
}

function Get-MIRFileHash {
  param([string]$Path)
  $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
  $algorithm = [Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '') }
  finally { $algorithm.Dispose(); $stream.Dispose() }
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
  $protected = [regex]::Replace($protected, '(?i)\b[A-Z]:[\\/]Users[\\/][^\\/\s]+', '<USER_PROFILE>')
  $protected = [regex]::Replace($protected, '(?i)(password|secret|api[_-]?key|access[_-]?token|token)\s*[:=]\s*[^\s,;]+', '$1=<REDACTED>')
  return $protected
}

function Add-MIRZipText {
  param([IO.Compression.ZipArchive]$Archive, [string]$Name, [string]$Value)
  $entry = $Archive.CreateEntry($Name, [IO.Compression.CompressionLevel]::Optimal)
  $writer = [IO.StreamWriter]::new($entry.Open(), $utf8)
  try { $writer.Write($Value) } finally { $writer.Dispose() }
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
    mir_archives = @()
    notes = @()
  }
  $logsFound = 0
  foreach ($name in @('factorio-current.log', 'factorio-previous.log')) {
    $path = Join-Path $userData $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $logsFound++
    $read = $null
    try {
      $read = Read-MIRBoundedFile -Path $path -Limit $maxLogBytes -Tail
    } catch {
      $manifest.notes += "$name could not be read; close Factorio and collect another report."
    }
    if ($null -eq $read) { continue }
    $safe = Protect-MIRLogText -Value $read.text
    Add-MIRZipText -Archive $archive -Name "logs/$name" -Value $safe
    $manifest.logs += [ordered]@{
      name = $name
      source_bytes = $read.bytes
      tail_truncated = $read.truncated
      captured_sha256 = Get-MIRTextHash -Value $safe
    }
  }
  if ($logsFound -eq 0) { $manifest.notes += 'No Factorio current or previous log was found.' }

  $modsDir = Join-Path $userData 'mods'
  $modListPath = Join-Path $modsDir 'mod-list.json'
  if (Test-Path -LiteralPath $modListPath -PathType Leaf) {
    $read = $null
    try {
      $read = Read-MIRBoundedFile -Path $modListPath -Limit $maxModListBytes
    } catch {
      $manifest.notes += 'mod-list.json could not be read; close Factorio and collect another report.'
    }
    if ($null -ne $read) {
      if ($null -ne $read.text) {
        Add-MIRZipText -Archive $archive -Name 'mods/mod-list.json' -Value $read.text
        $manifest.mod_list = [ordered]@{ bytes = $read.bytes; captured_sha256 = Get-MIRTextHash -Value $read.text }
      } else {
        $manifest.notes += 'mod-list.json exceeded 2 MiB and was omitted.'
      }
    }
  }
  $modSettingsPath = Join-Path $modsDir 'mod-settings.dat'
  if (Test-Path -LiteralPath $modSettingsPath -PathType Leaf) {
    try {
      $manifest.mod_settings = [ordered]@{
        name = 'mod-settings.dat'
        sha256 = Get-MIRFileHash -Path $modSettingsPath
        included = $false
      }
    } catch {
      $manifest.notes += 'mod-settings.dat could not be hashed; close Factorio and collect another report.'
    }
  }
  $mirArchiveCount = 0
  $mirListOk = $true
  if (Test-Path -LiteralPath $modsDir -PathType Container) {
    try {
      $mirFiles = @(Get-ChildItem -LiteralPath $modsDir -File -Filter 'more-infinite-research_*.zip' | Sort-Object Name)
      $mirArchiveCount = $mirFiles.Count
      foreach ($file in $mirFiles) {
        try {
          $manifest.mir_archives += [ordered]@{ name = $file.Name; bytes = $file.Length; sha256 = Get-MIRFileHash -Path $file.FullName }
        } catch {
          $manifest.notes += "$($file.Name) could not be hashed; close Factorio and collect another report."
        }
      }
    } catch {
      $mirListOk = $false
      $manifest.notes += 'The mods directory could not be listed; close Factorio and collect another report.'
    }
  }
  if ($mirListOk -and $mirArchiveCount -eq 0) { $manifest.notes += 'No MIR ZIP was found in the selected mods directory.' }

  Add-MIRZipText -Archive $archive -Name 'README.txt' -Value @'
MIR startup support report

This archive works even when MIR or Factorio stops during startup. It contains
the available current and previous Factorio logs, the active mod list, and
MIR package identities. Long logs include their last 8 MiB. User paths and
common password/token assignments are redacted from captured logs.

The binary mod-settings.dat is NOT included; its hash is recorded for identity.
No saves, crash dumps, full mod packages, or unrelated personal files are
included. Review the archive before sharing it. If a maintainer needs exact
startup settings or an unredacted line, provide those separately by choice.
'@
  Add-MIRZipText -Archive $archive -Name 'manifest.json' -Value (($manifest | ConvertTo-Json -Depth 8) + "`n")
} finally {
  $archive.Dispose()
  $stream.Dispose()
}

Write-Output "MIR support report: $outputPath"
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
