Set-StrictMode -Version Latest

$script:MIR42SupportCollectorAssetName = 'MIR42-Offline-Support-Collector.zip'
$script:MIR42SupportCollectorScripts = @('Collect-MIRPlayerReport.cmd', 'Collect-MIRPlayerReport.ps1')

function Read-MIR42SupportCollectorSourceBlob {
  param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$SourceCommit, [Parameter(Mandatory)][string]$Name)
  if ($SourceCommit -cnotmatch '^[A-Fa-f0-9]{40}$' -or $Name -cnotin $script:MIR42SupportCollectorScripts) {
    throw '[mir42-support-collector-source-identity]'
  }
  $start = [Diagnostics.ProcessStartInfo]::new('git')
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  foreach ($argument in @('-C', $RepoRoot, 'show', "${SourceCommit}:scripts/$Name")) { [void]$start.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::Start($start)
  $bytes = [IO.MemoryStream]::new()
  try {
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.StandardOutput.BaseStream.CopyTo($bytes)
    $process.WaitForExit()
    if ($process.ExitCode -ne 0 -or $bytes.Length -le 0 -or $bytes.Length -gt 1048576) {
      throw "[mir42-support-collector-source-blob] $Name $($stderr.GetAwaiter().GetResult())"
    }
    return $bytes.ToArray()
  } finally { $bytes.Dispose(); $process.Dispose() }
}

function Assert-MIR42SupportCollectorBundle {
  param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$SourceCommit, [Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw '[mir42-support-collector-bundle-missing]' }
  Add-Type -AssemblyName System.IO.Compression
  $stream = [IO.File]::OpenRead($Path)
  try {
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $true)
    try {
      $entries = @($archive.Entries)
      if ($entries.Count -ne $script:MIR42SupportCollectorScripts.Count) { throw '[mir42-support-collector-bundle-entry-count]' }
      for ($index = 0; $index -lt $script:MIR42SupportCollectorScripts.Count; $index++) {
        $name = $script:MIR42SupportCollectorScripts[$index]
        $entry = $entries[$index]
        if ([string]$entry.FullName -cne $name -or $entry.Length -le 0 -or $entry.Length -gt 1048576) {
          throw "[mir42-support-collector-bundle-entry] $name"
        }
        $expected = Read-MIR42SupportCollectorSourceBlob -RepoRoot $RepoRoot -SourceCommit $SourceCommit -Name $name
        $actual = [IO.MemoryStream]::new()
        try {
          $entryStream = $entry.Open()
          try { $entryStream.CopyTo($actual) } finally { $entryStream.Dispose() }
          $actualHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($actual.ToArray()))
          $expectedHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($expected))
          if ($actual.Length -ne $expected.Length -or $actualHash -cne $expectedHash) {
            throw "[mir42-support-collector-bundle-source-drift] $name"
          }
        } finally { $actual.Dispose() }
      }
    } finally { $archive.Dispose() }
  } finally { $stream.Dispose() }
  $item = Get-Item -LiteralPath $Path
  return [pscustomobject][ordered]@{path=[string]$item.Name;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64]$item.Length}
}

function New-MIR42SupportCollectorBundle {
  param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$SourceCommit, [Parameter(Mandatory)][string]$OutputPath)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if ([IO.Path]::GetFileName($OutputPath) -cne $script:MIR42SupportCollectorAssetName) { throw '[mir42-support-collector-output-name]' }
  if (Test-Path -LiteralPath $OutputPath) { throw '[mir42-support-collector-output-exists]' }
  $parent = Split-Path -Parent $OutputPath
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $parent) }
  Add-Type -AssemblyName System.IO.Compression
  $stream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try {
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
      foreach ($name in $script:MIR42SupportCollectorScripts) {
        $bytes = Read-MIR42SupportCollectorSourceBlob -RepoRoot $repo -SourceCommit $SourceCommit -Name $name
        $entry = $archive.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        $entryStream = $entry.Open()
        try { $entryStream.Write($bytes, 0, $bytes.Length) } finally { $entryStream.Dispose() }
      }
    } finally { $archive.Dispose() }
  } finally { $stream.Dispose() }
  return Assert-MIR42SupportCollectorBundle -RepoRoot $repo -SourceCommit $SourceCommit -Path $OutputPath
}
