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

function Test-MIRTextFingerprintPath {
  param([Parameter(Mandatory)][string]$RelativePath)

  $extension = [System.IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
  if ($extension -in @(".cfg", ".json", ".jsonl", ".lua", ".md", ".ps1", ".psm1", ".txt", ".yml", ".yaml")) {
    return $true
  }

  return [System.IO.Path]::GetFileName($RelativePath) -eq "LICENSE"
}

function Get-MIRNormalizedTextIdentity {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

  $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
  $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($normalized)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return [pscustomobject]@{
      Length = $bytes.Length
      Sha256 = [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "")
    }
  } finally {
    $sha.Dispose()
  }
}

function Get-MIRFileContentIdentity {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$RelativePath
  )

  if (Test-MIRTextFingerprintPath -RelativePath $RelativePath) {
    return Get-MIRNormalizedTextIdentity -Text ([System.IO.File]::ReadAllText($Path))
  }

  $item = Get-Item -LiteralPath $Path
  return [pscustomobject]@{
    Length = $item.Length
    Sha256 = Get-MIRFileSha256 -Path $Path
  }
}

function Get-MIRFileContentSha256 {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$RelativePath
  )

  return (Get-MIRFileContentIdentity -Path $Path -RelativePath $RelativePath).Sha256
}

function Get-MIRZipEntryContentIdentity {
  param(
    [Parameter(Mandatory)]$Entry,
    [Parameter(Mandatory)][string]$RelativePath
  )

  $stream = $Entry.Open()
  try {
    if (Test-MIRTextFingerprintPath -RelativePath $RelativePath) {
      $reader = [System.IO.StreamReader]::new(
        $stream,
        [System.Text.UTF8Encoding]::new($false),
        $true,
        1024,
        $true
      )
      try {
        return Get-MIRNormalizedTextIdentity -Text $reader.ReadToEnd()
      } finally {
        $reader.Dispose()
      }
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      return [pscustomobject]@{
        Length = $Entry.Length
        Sha256 = [System.BitConverter]::ToString($sha.ComputeHash($stream)).Replace("-", "")
      }
    } finally {
      $sha.Dispose()
    }
  } finally {
    $stream.Dispose()
  }
}

function Get-MIRPackageSourceFingerprint {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $rows = @(
    foreach ($relative in Get-MIRPackageSourceFiles -RepoRoot $repo) {
      $path = Join-Path $repo $relative
      $identity = Get-MIRFileContentIdentity -Path $path -RelativePath $relative
      "{0}`t{1}`t{2}" -f $relative, $identity.Length, $identity.Sha256
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
  $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $rows = @(
      foreach ($entry in @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | Sort-Object FullName)) {
        $slash = $entry.FullName.IndexOf("/")
        $relative = if ($slash -ge 0) { $entry.FullName.Substring($slash + 1) } else { $entry.FullName }
        $identity = Get-MIRZipEntryContentIdentity -Entry $entry -RelativePath $relative
        "{0}`t{1}`t{2}" -f $relative, $identity.Length, $identity.Sha256
      }
    )
    return Get-MIRStringSha256 -Value ($rows -join "`n")
  } finally {
    $zip.Dispose()
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

function Test-MIRRepositoryGitDirty {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $status = @(& git -C $RepoRoot status --porcelain --untracked-files=all 2>$null)
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect repository Git state."
  }
  return $status.Count -gt 0
}

function Get-MIRValidationHarnessRoots {
  return @("scripts", "fixtures", ".mir", ".github/workflows")
}

function Test-MIRValidationHarnessEvidencePath {
  param([Parameter(Mandatory)][string]$RelativePath)

  return $RelativePath -match '^\.mir/(evidence|target-lines)/' -or $RelativePath -in @(
    '.mir/branches.yml',
    '.mir/compatibility.yml',
    '.mir/convergence.yml',
    '.mir/release-wave.yml'
  )
}

function Get-MIRValidationHarnessFingerprint {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $files = @()
  foreach ($relative in Get-MIRValidationHarnessRoots) {
    $path = Join-Path $repo $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $files += $relative.Replace("\", "/")
    } elseif (Test-Path -LiteralPath $path -PathType Container) {
      $files += @(Get-ChildItem -LiteralPath $path -Recurse -File | ForEach-Object {
        [System.IO.Path]::GetRelativePath($repo, $_.FullName).Replace("\", "/")
      })
    }
  }
  $files = @($files | Where-Object { -not (Test-MIRValidationHarnessEvidencePath -RelativePath $_) })
  $rows = foreach ($relative in @($files | Sort-Object -Unique)) {
    $path = Join-Path $repo $relative
    $identity = Get-MIRFileContentIdentity -Path $path -RelativePath $relative
    "{0}`t{1}`t{2}" -f $relative, $identity.Length, $identity.Sha256
  }
  return Get-MIRStringSha256 -Value ($rows -join "`n")
}

function Test-MIRValidationHarnessGitDirty {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $roots = @(Get-MIRValidationHarnessRoots)
  $status = @(& git -C $RepoRoot status --porcelain --untracked-files=all -- @roots 2>$null)
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect validation harness Git state."
  }
  $relevant = @($status | Where-Object {
    $relative = ($_ -replace '^..\s+', '').Replace("\", "/")
    -not (Test-MIRValidationHarnessEvidencePath -RelativePath $relative)
  })
  return $relevant.Count -gt 0
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
