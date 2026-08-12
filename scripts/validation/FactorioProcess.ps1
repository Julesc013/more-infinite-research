function Invoke-FactorioProcess {
  param(
    [string]$FilePath,
    [string[]]$Arguments,
    [int]$TimeoutMs = 300000
  )

  $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $processInfo.FileName = $FilePath
  $processInfo.UseShellExecute = $false
  $processInfo.CreateNoWindow = $true
  $processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
  foreach ($arg in $Arguments) {
    [void]$processInfo.ArgumentList.Add($arg)
  }

  $process = [System.Diagnostics.Process]::Start($processInfo)
  if (-not $process.WaitForExit($TimeoutMs)) {
    try {
      $process.Kill($true)
    } catch {
      $process.Kill()
    }
    throw "Factorio runtime validation timed out after $TimeoutMs ms."
  }
  return $process.ExitCode
}

function Get-MIRCompactScenarioPathSegment {
  param([Parameter(Mandatory)][string]$ScenarioName)

  $bytes = [Text.Encoding]::UTF8.GetBytes($ScenarioName)
  $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
  return "s-$($digest.Substring(0, 16))"
}

function Assert-MIRFactorioPathBudget {
  param(
    [Parameter(Mandatory)][string]$Path,
    [string]$Context = "Factorio validation path",
    [int]$MaximumLength = 240
  )

  $fullPath = [IO.Path]::GetFullPath($Path)
  if ($fullPath.Length -gt $MaximumLength) {
    throw "$Context exceeds the conservative Factorio path budget ($($fullPath.Length) > $MaximumLength): $fullPath"
  }
}

function Remove-MIRCopiedModDirectory {
  param([string]$Name, [string]$ModsDir)
  $modsRootWithSeparator = (Resolve-Path -LiteralPath $ModsDir).Path.TrimEnd("\") + "\"
  $target = Join-Path $ModsDir $Name
  if (Test-Path -LiteralPath $target) {
    $resolvedTarget = (Resolve-Path -LiteralPath $target).Path
    if (-not $resolvedTarget.StartsWith($modsRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove mod directory outside scenario mods root: $resolvedTarget"
    }
    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
  }
  return $target
}

function Copy-MIRModDirectory {
  param([string]$Source, [string]$Name, [string]$ModsDir)
  $target = Remove-MIRCopiedModDirectory -Name $Name -ModsDir $ModsDir
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  $sourceRoot = (Resolve-Path -LiteralPath $Source).Path
  foreach ($directory in Get-ChildItem -LiteralPath $sourceRoot -Recurse -Directory) {
    $relative = [System.IO.Path]::GetRelativePath($sourceRoot, $directory.FullName)
    New-Item -ItemType Directory -Force -Path (Join-Path $target $relative) | Out-Null
  }
  foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -Recurse -File) {
    $relative = [System.IO.Path]::GetRelativePath($sourceRoot, $file.FullName)
    $destination = Join-Path $target $relative
    try {
      New-Item -ItemType HardLink -Path $destination -Target $file.FullName -ErrorAction Stop | Out-Null
    } catch {
      Copy-Item -LiteralPath $file.FullName -Destination $destination
    }
  }
}

function Publish-MIRModDirectoryArchive {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$ModsDir
  )

  if ($Name -notmatch '^[a-zA-Z0-9_-]+$' -or $Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Cannot publish validation fixture with unsafe identity '$Name' version '$Version'."
  }
  $sourceRoot = (Resolve-Path -LiteralPath $Source).Path
  $info = Get-Content -Raw -LiteralPath (Join-Path $sourceRoot "info.json") | ConvertFrom-Json
  if ([string]$info.name -cne $Name -or [string]$info.version -cne $Version) {
    throw "Validation fixture identity differs from its info.json: $Source"
  }

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archiveRoot = "${Name}_${Version}"
  $finalPath = Join-Path $ModsDir "$archiveRoot.zip"
  Assert-MIRFactorioPathBudget -Path $finalPath -Context "Validation fixture archive path"
  $temporaryPath = Join-Path $ModsDir (".{0}-{1}.zip" -f $Name, [guid]::NewGuid().ToString("N"))
  $sourceFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Sort-Object FullName)
  $expectedEntries = @($sourceFiles | ForEach-Object {
    "$archiveRoot/$([IO.Path]::GetRelativePath($sourceRoot, $_.FullName).Replace('\', '/'))"
  } | Sort-Object)
  try {
    $archive = [IO.Compression.ZipFile]::Open($temporaryPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
      foreach ($file in $sourceFiles) {
        $relative = [IO.Path]::GetRelativePath($sourceRoot, $file.FullName).Replace("\", "/")
        $entry = $archive.CreateEntry("$archiveRoot/$relative", [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        $inputStream = [IO.File]::OpenRead($file.FullName)
        $outputStream = $entry.Open()
        try {
          $inputStream.CopyTo($outputStream)
        } finally {
          $outputStream.Dispose()
          $inputStream.Dispose()
        }
      }
    } finally {
      $archive.Dispose()
    }
    $archive = [IO.Compression.ZipFile]::OpenRead($temporaryPath)
    try {
      $actualEntries = @($archive.Entries | ForEach-Object { [string]$_.FullName } | Sort-Object)
      if (($actualEntries -join "`n") -cne ($expectedEntries -join "`n")) {
        throw "Validation fixture archive has unexpected entries: $Name $Version"
      }
    } finally {
      $archive.Dispose()
    }
    Move-Item -LiteralPath $temporaryPath -Destination $finalPath -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
      Remove-Item -LiteralPath $temporaryPath -Force
    }
  }
  if (-not (Test-Path -LiteralPath $finalPath -PathType Leaf)) {
    throw "Validation fixture archive was not published: $Name $Version"
  }
  return $finalPath
}

function Copy-MIRFileWithHardlinkFallback {
  param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
  if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
  try {
    New-Item -ItemType HardLink -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
  } catch {
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
  }
}

function Copy-MIRRepositoryModDirectory {
  param([string]$RepoRoot, [string]$ModsDir)

  $target = Remove-MIRCopiedModDirectory -Name "more-infinite-research" -ModsDir $ModsDir
  New-Item -ItemType Directory -Force -Path $target | Out-Null

  foreach ($file in @(
    "changelog.txt",
    "control.lua",
    "data-final-fixes.lua",
    "data-updates.lua",
    "data.lua",
    "info.json",
    "LICENSE",
    "README.md",
    "settings.lua",
    "thumbnail.png"
  )) {
    $source = Join-Path $RepoRoot $file
    if (Test-Path -LiteralPath $source) {
      Copy-Item -LiteralPath $source -Destination (Join-Path $target $file)
    }
  }

  foreach ($directory in @("migrations", "locale", "prototypes")) {
    $source = Join-Path $RepoRoot $directory
    if (Test-Path -LiteralPath $source) {
      Copy-Item -LiteralPath $source -Destination (Join-Path $target $directory) -Recurse
    }
  }
}
