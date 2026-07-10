function Get-MIRPackageSourceRoots {
  return @(
    "changelog.txt",
    "control.lua",
    "data-final-fixes.lua",
    "data-updates.lua",
    "data.lua",
    "info.json",
    "LICENSE",
    "README.md",
    "settings.lua",
    "thumbnail.png",
    "locale",
    "migrations",
    "prototypes"
  )
}

function Get-MIRPackageSourceFiles {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $files = @()
  foreach ($relative in Get-MIRPackageSourceRoots) {
    $path = Join-Path $repo $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $files += $relative.Replace("\", "/")
      continue
    }
    if (Test-Path -LiteralPath $path -PathType Container) {
      $files += @(
        Get-ChildItem -LiteralPath $path -Recurse -File |
          ForEach-Object { [System.IO.Path]::GetRelativePath($repo, $_.FullName).Replace("\", "/") }
      )
    }
  }

  return @($files | Sort-Object -Unique)
}

function Get-MIRStringSha256 {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    return [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "")
  } finally {
    $sha.Dispose()
  }
}

function Get-MIRFileSha256 {
  param([Parameter(Mandatory)][string]$Path)

  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-MIRPackageSourceFingerprint {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $rows = @(
    foreach ($relative in Get-MIRPackageSourceFiles -RepoRoot $repo) {
      $path = Join-Path $repo $relative
      $item = Get-Item -LiteralPath $path
      "{0}`t{1}`t{2}" -f $relative, $item.Length, (Get-MIRFileSha256 -Path $path)
    }
  )
  return Get-MIRStringSha256 -Value ($rows -join "`n")
}

function Get-MIRTargetProfileFingerprint {
  param([Parameter(Mandatory)]$Profile)

  $json = $Profile | ConvertTo-Json -Depth 30 -Compress
  return Get-MIRStringSha256 -Value $json
}

function Get-MIRRequiredGroupsFingerprint {
  param([string[]]$RequiredGroups = @())

  $groups = @($RequiredGroups | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  return Get-MIRStringSha256 -Value ($groups -join "`n")
}

function Get-MIRZipContentFingerprint {
  param([Parameter(Mandatory)][string]$Path)

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $rows = @(
      foreach ($entry in @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | Sort-Object FullName)) {
        $stream = $entry.Open()
        try {
          $entryHash = [System.BitConverter]::ToString($sha.ComputeHash($stream)).Replace("-", "")
        } finally {
          $stream.Dispose()
        }
        $slash = $entry.FullName.IndexOf("/")
        $relative = if ($slash -ge 0) { $entry.FullName.Substring($slash + 1) } else { $entry.FullName }
        "{0}`t{1}`t{2}" -f $relative, $entry.Length, $entryHash
      }
    )
    return Get-MIRStringSha256 -Value ($rows -join "`n")
  } finally {
    $zip.Dispose()
    $sha.Dispose()
  }
}

function Get-MIRGitCommit {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $value = (& git -C $RepoRoot rev-parse HEAD 2>$null)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($value)) {
    throw "Unable to resolve the current Git commit."
  }
  return ([string]$value).Trim()
}

function Test-MIRPackageSourceGitDirty {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $roots = @(Get-MIRPackageSourceRoots)
  $status = @(& git -C $RepoRoot status --porcelain -- @roots 2>$null)
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect package-visible Git state."
  }
  return $status.Count -gt 0
}

function Get-MIRFactorioBinaryVersion {
  param([Parameter(Mandatory)][string]$Path)

  $item = Get-Item -LiteralPath $Path
  $version = [string]$item.VersionInfo.ProductVersion
  if ([string]::IsNullOrWhiteSpace($version)) {
    $version = [string]$item.VersionInfo.FileVersion
  }
  if ([string]::IsNullOrWhiteSpace($version)) {
    $version = "unknown"
  }
  return $version.Trim()
}
