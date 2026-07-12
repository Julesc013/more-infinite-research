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
