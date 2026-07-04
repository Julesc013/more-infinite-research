. (Join-Path $PSScriptRoot "Checkpoint.ps1")

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Read-MIRZipInfoJson {
  param([Parameter(Mandatory)][string]$ZipPath)

  $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    $entry = $zip.Entries | Where-Object { $_.FullName -match '^[^/]+/info\.json$' } | Select-Object -First 1
    if (-not $entry) { throw "Missing info.json in $ZipPath" }
    $stream = $entry.Open()
    try {
      $reader = New-Object System.IO.StreamReader($stream)
      try {
        return ($reader.ReadToEnd() | ConvertFrom-Json)
      } finally {
        $reader.Dispose()
      }
    } finally {
      $stream.Dispose()
    }
  } finally {
    $zip.Dispose()
  }
}

function New-MIRLocalModIndex {
  param(
    [Parameter(Mandatory)][string[]]$Dirs,
    [Parameter(Mandatory)][string]$OutputPath
  )

  $mods = @()
  foreach ($dir in $Dirs) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($zip in Get-ChildItem -LiteralPath $dir -Filter *.zip -File) {
      try {
        $info = Read-MIRZipInfoJson -ZipPath $zip.FullName
        $hash = Get-FileHash -Algorithm SHA1 -LiteralPath $zip.FullName
        $mods += [ordered]@{
          name = [string]$info.name
          version = [string]$info.version
          factorio_version = [string]$info.factorio_version
          title = [string]$info.title
          sha1 = $hash.Hash.ToLowerInvariant()
          path = $zip.FullName
          size = $zip.Length
          mtime = $zip.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
          dependencies = @($info.dependencies | ForEach-Object { [string]$_ })
        }
      } catch {
        $mods += [ordered]@{
          name = ""
          version = ""
          factorio_version = ""
          title = ""
          sha1 = ""
          path = $zip.FullName
          size = $zip.Length
          mtime = $zip.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
          dependencies = @()
          error = $_.Exception.Message
        }
      }
    }
  }

  $index = [ordered]@{
    schema = 1
    generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    dirs = @($Dirs)
    count = $mods.Count
    mods = @($mods | Sort-Object name, version)
  }
  Write-MIRJsonAtomic -Path $OutputPath -Data $index
  return [pscustomobject]$index
}
