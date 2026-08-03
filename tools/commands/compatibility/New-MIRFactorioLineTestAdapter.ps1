[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$SourceArchive,

  [Parameter(Mandatory = $true)]
  [string]$OutputArchive,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^\d+\.\d+$')]
  [string]$ExpectedSourceFactorioVersion,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^\d+\.\d+$')]
  [string]$TargetFactorioVersion,

  [string]$ManifestPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-MIRSha256 {
  param([Parameter(Mandatory = $true)][string]$LiteralPath)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $LiteralPath).Hash.ToUpperInvariant()
}

function Get-MIRStreamSha256 {
  param([Parameter(Mandatory = $true)][System.IO.Stream]$Stream)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($Stream))).Replace("-", "")
  } finally {
    $sha.Dispose()
  }
}

function Get-MIRArchiveEntries {
  param([Parameter(Mandatory = $true)][string]$LiteralPath)
  $archive = [System.IO.Compression.ZipFile]::OpenRead($LiteralPath)
  try {
    $rows = @()
    foreach ($entry in @($archive.Entries | Sort-Object FullName)) {
      if ([string]::IsNullOrEmpty($entry.Name)) {
        continue
      }
      $stream = $entry.Open()
      try {
        $rows += [pscustomobject][ordered]@{
          path = $entry.FullName
          bytes = [long]$entry.Length
          sha256 = Get-MIRStreamSha256 -Stream $stream
        }
      } finally {
        $stream.Dispose()
      }
    }
    return @($rows)
  } finally {
    $archive.Dispose()
  }
}

function Get-MIRAggregateEntryHash {
  param([Parameter(Mandatory = $true)][object[]]$Entries)
  $material = (($Entries | ForEach-Object {
    "$($_.path)`t$($_.bytes)`t$($_.sha256)"
  }) -join "`n")
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($material)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "")
  } finally {
    $sha.Dispose()
  }
}

$source = [System.IO.Path]::GetFullPath($SourceArchive)
$output = [System.IO.Path]::GetFullPath($OutputArchive)
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
  throw "Source archive does not exist: $source"
}
if ([System.IO.Path]::GetExtension($source) -ne ".zip" -or
    [System.IO.Path]::GetExtension($output) -ne ".zip") {
  throw "SourceArchive and OutputArchive must be ZIP files."
}
if ($source -eq $output) {
  throw "The test adapter refuses to overwrite its source archive."
}
if ($ExpectedSourceFactorioVersion -eq $TargetFactorioVersion) {
  throw "Source and target Factorio versions must differ."
}

$outputDirectory = Split-Path -Parent $output
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$temporary = "$output.partial"
if (Test-Path -LiteralPath $temporary) {
  Remove-Item -LiteralPath $temporary -Force
}

$sourceZip = [System.IO.Compression.ZipFile]::OpenRead($source)
$outputStream = [System.IO.File]::Open(
  $temporary,
  [System.IO.FileMode]::CreateNew,
  [System.IO.FileAccess]::ReadWrite,
  [System.IO.FileShare]::None
)
$outputZip = [System.IO.Compression.ZipArchive]::new(
  $outputStream,
  [System.IO.Compression.ZipArchiveMode]::Create,
  $true
)

$infoEntryPath = $null
$modName = $null
$modVersion = $null
try {
  foreach ($sourceEntry in @($sourceZip.Entries | Sort-Object FullName)) {
    $targetEntry = $outputZip.CreateEntry(
      $sourceEntry.FullName,
      [System.IO.Compression.CompressionLevel]::Optimal
    )
    $targetEntry.LastWriteTime = $sourceEntry.LastWriteTime

    if ([string]::IsNullOrEmpty($sourceEntry.Name)) {
      continue
    }

    $sourceEntryStream = $sourceEntry.Open()
    $targetEntryStream = $targetEntry.Open()
    try {
      if ($sourceEntry.FullName -match '(^|/)info\.json$') {
        if ($null -ne $infoEntryPath) {
          throw "Archive contains more than one info.json entry."
        }
        $reader = [System.IO.StreamReader]::new(
          $sourceEntryStream,
          [System.Text.Encoding]::UTF8,
          $true
        )
        try {
          $infoText = $reader.ReadToEnd()
        } finally {
          $reader.Dispose()
        }
        $info = $infoText | ConvertFrom-Json
        if ([string]$info.factorio_version -ne $ExpectedSourceFactorioVersion) {
          throw "Expected Factorio $ExpectedSourceFactorioVersion, found $($info.factorio_version)."
        }
        $needle = '("factorio_version"\s*:\s*)"' +
          [regex]::Escape($ExpectedSourceFactorioVersion) + '"'
        $replacement = '${1}"' + $TargetFactorioVersion + '"'
        $adaptedText = [regex]::Replace($infoText, $needle, $replacement)
        if ($adaptedText -eq $infoText) {
          throw "The declared Factorio version was not replaced."
        }
        $writer = [System.IO.StreamWriter]::new(
          $targetEntryStream,
          [System.Text.UTF8Encoding]::new($false)
        )
        try {
          $writer.Write($adaptedText)
          $writer.Flush()
        } finally {
          $writer.Dispose()
        }
        $infoEntryPath = $sourceEntry.FullName
        $modName = [string]$info.name
        $modVersion = [string]$info.version
      } else {
        $sourceEntryStream.CopyTo($targetEntryStream)
      }
    } finally {
      $sourceEntryStream.Dispose()
      $targetEntryStream.Dispose()
    }
  }
} finally {
  $outputZip.Dispose()
  $outputStream.Dispose()
  $sourceZip.Dispose()
}

if ($null -eq $infoEntryPath) {
  Remove-Item -LiteralPath $temporary -Force
  throw "Archive contains no info.json entry."
}

$sourceEntries = @(Get-MIRArchiveEntries -LiteralPath $source)
$adaptedEntries = @(Get-MIRArchiveEntries -LiteralPath $temporary)
if ($sourceEntries.Count -ne $adaptedEntries.Count) {
  Remove-Item -LiteralPath $temporary -Force
  throw "Adapted archive entry count changed."
}

$changed = @()
for ($index = 0; $index -lt $sourceEntries.Count; $index++) {
  $before = $sourceEntries[$index]
  $after = $adaptedEntries[$index]
  if ($before.path -ne $after.path) {
    Remove-Item -LiteralPath $temporary -Force
    throw "Adapted archive entry ordering or identity changed."
  }
  if ($before.sha256 -ne $after.sha256) {
    $changed += [string]$before.path
  }
}
if ($changed.Count -ne 1 -or $changed[0] -ne $infoEntryPath) {
  Remove-Item -LiteralPath $temporary -Force
  throw "Only info.json may change; observed: $($changed -join ', ')"
}

if (Test-Path -LiteralPath $output) {
  Remove-Item -LiteralPath $output -Force
}
Move-Item -LiteralPath $temporary -Destination $output

$payloadSource = @($sourceEntries | Where-Object { $_.path -ne $infoEntryPath })
$payloadAdapted = @($adaptedEntries | Where-Object { $_.path -ne $infoEntryPath })
$sourcePayloadHash = Get-MIRAggregateEntryHash -Entries $payloadSource
$adaptedPayloadHash = Get-MIRAggregateEntryHash -Entries $payloadAdapted
if ($sourcePayloadHash -ne $adaptedPayloadHash) {
  throw "Non-metadata payload identity changed."
}

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
  $ManifestPath = "$output.adapter-manifest.json"
}
$manifest = [System.IO.Path]::GetFullPath($ManifestPath)
$manifestDirectory = Split-Path -Parent $manifest
New-Item -ItemType Directory -Force -Path $manifestDirectory | Out-Null

$record = [pscustomobject][ordered]@{
  schema = 1
  kind = "factorio-line-test-adapter"
  purpose = "test-only; not a distributable compatibility archive"
  mod = [pscustomobject][ordered]@{
    name = $modName
    version = $modVersion
  }
  source = [pscustomobject][ordered]@{
    archive = $source
    archive_sha256 = Get-MIRSha256 -LiteralPath $source
    factorio_version = $ExpectedSourceFactorioVersion
  }
  adapted = [pscustomobject][ordered]@{
    archive = $output
    archive_sha256 = Get-MIRSha256 -LiteralPath $output
    factorio_version = $TargetFactorioVersion
  }
  verification = [pscustomobject][ordered]@{
    entry_count = $sourceEntries.Count
    changed_entries = @($changed)
    unchanged_payload_entries = $payloadSource.Count
    unchanged_payload_sha256 = $sourcePayloadHash
  }
}
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifest -Encoding UTF8

Write-Host "[ok] Created test-only Factorio-line adapter for $modName $modVersion."
Write-Host "     source:  $($record.source.archive_sha256)"
Write-Host "     adapted: $($record.adapted.archive_sha256)"
Write-Host "     payload: $($record.verification.unchanged_payload_sha256)"
Write-Host "     manifest: $manifest"
