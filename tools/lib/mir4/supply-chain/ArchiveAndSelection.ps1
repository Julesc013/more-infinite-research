function Get-MIR4SupplyChainCanonicalArchiveRows {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = Resolve-MIR4SupplyChainRepoRoot -RepoRoot $RepoRoot
  $scratchRoot = Assert-MIR4DescendantPath -Root $repo -Path (Join-Path $repo 'build/results/mir4-t15/supply-chain-source-scratch')
  if (-not (Test-Path -LiteralPath $scratchRoot -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null
  }
  $archivePath = Assert-MIR4DescendantPath -Root $scratchRoot -Path (Join-Path $scratchRoot ("source-" + [guid]::NewGuid().ToString('N') + '.zip'))
  $git = @(Get-Command git -CommandType Application -ErrorAction Stop | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_.Source) -and
    (Test-Path -LiteralPath $_.Source -PathType Leaf)
  } | Select-Object -First 1)
  if ($git.Count -ne 1) { throw '[mir4-supply-chain-git-executable]' }
  try {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = [string]$git[0].Source
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in @(
      '-c', 'core.autocrlf=false',
      '-c', 'core.eol=lf',
      '-C', $repo,
      'archive', '--format=zip', '--prefix=mir4-source/',
      "--output=$archivePath", 'HEAD'
    )) {
      $null = $info.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    if (-not $process.Start()) { throw '[mir4-supply-chain-git-archive-start]' }
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $process.Dispose()
    if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
      throw "[mir4-supply-chain-git-archive] $standardError $standardOutput"
    }
    $archiveRows = @(Get-MIR4SupplyChainArchiveRows -Path $archivePath -MaximumEntries 100000 -MaximumExpandedBytes 1073741824)
    return @(
      foreach ($entry in $archiveRows) {
        $archivePathValue = [string]$entry.path
        if (-not $archivePathValue.StartsWith('mir4-source/', [StringComparison]::Ordinal)) {
          throw "[mir4-supply-chain-git-archive-root] $archivePathValue"
        }
        $relative = $archivePathValue.Substring('mir4-source/'.Length)
        Assert-MIR4SupplyChainRelativePath -Path $relative
        [pscustomobject][ordered]@{
          path = $relative
          bytes = [long]$entry.bytes
          sha256 = [string]$entry.sha256
          source_class = Get-MIR4SupplyChainFileClass -Path $relative
          origin = 'repository'
        }
      }
    )
  } finally {
    if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
      Remove-Item -LiteralPath $archivePath -Force
    }
  }
}

function Select-MIR4SupplyChainRows {
  param(
    [Parameter(Mandatory)][object[]]$Rows,
    [Parameter(Mandatory)][string[]]$Paths
  )

  $map = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($row in $Rows) { $map.Add([string]$row.path, $row) }
  $selectedPaths = @(
    $Paths |
      ForEach-Object { ([string]$_).Replace('\', '/') } |
      Sort-Object -Unique -CaseSensitive
  )
  if ($selectedPaths.Count -eq 0) { throw '[mir4-supply-chain-row-selection-empty]' }
  return @(
    foreach ($path in $selectedPaths) {
      Assert-MIR4SupplyChainRelativePath -Path $path
      if (-not $map.ContainsKey($path)) { throw "[mir4-supply-chain-row-path-absent] $path" }
      $map[$path]
    }
  )
}

function Get-MIR4SupplyChainRepositoryRows {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return @(Get-MIR4SupplyChainCanonicalArchiveRows -RepoRoot $RepoRoot)
}

function Get-MIR4SupplyChainPackageRows {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $rows = @(Get-MIR4SupplyChainCanonicalArchiveRows -RepoRoot $RepoRoot)
  return @(Select-MIR4SupplyChainRows -Rows $rows -Paths @(Get-MIRPackageSourceFiles -RepoRoot $RepoRoot))
}

function Get-MIR4SupplyChainExplicitRows {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string[]]$Paths
  )
  $rows = @(Get-MIR4SupplyChainCanonicalArchiveRows -RepoRoot $RepoRoot)
  return @(Select-MIR4SupplyChainRows -Rows $rows -Paths $Paths)
}

function Get-MIR4SupplyChainArchiveRows {
  param(
    [Parameter(Mandatory)][string]$Path,
    [ValidateRange(1, 100000)][int]$MaximumEntries = 16384,
    [ValidateRange(1, 9223372036854775807)][long]$MaximumExpandedBytes = 2147483648
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $zip = [IO.Compression.ZipFile]::OpenRead($resolved)
  $rows = [Collections.Generic.List[object]]::new()
  $pathMap = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
  [long]$expanded = 0
  try {
    if ($zip.Entries.Count -eq 0 -or $zip.Entries.Count -gt $MaximumEntries) {
      throw "MIR 4 supply-chain archive has an invalid bounded entry count: $Path"
    }
    foreach ($entry in @($zip.Entries | Sort-Object FullName -CaseSensitive)) {
      if ([string]::IsNullOrEmpty($entry.Name)) { continue }
      $relative = ([string]$entry.FullName).Replace('\', '/')
      Assert-MIR4SupplyChainRelativePath -Path $relative
      if ($pathMap.ContainsKey($relative)) {
        throw "Duplicate or ordinal-case-colliding MIR 4 archive path: $($pathMap[$relative]) and $relative"
      }
      $pathMap.Add($relative, $relative)
      $expanded += [long]$entry.Length
      if ($expanded -gt $MaximumExpandedBytes) {
        throw "MIR 4 supply-chain archive exceeds the bounded expanded size: $Path"
      }
      $stream = $entry.Open()
      $sha = [Security.Cryptography.SHA256]::Create()
      try {
        $digest = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '')
      } finally {
        $sha.Dispose()
        $stream.Dispose()
      }
      $rows.Add([pscustomobject][ordered]@{
        path = $relative
        bytes = [long]$entry.Length
        sha256 = $digest
        source_class = Get-MIR4SupplyChainFileClass -Path $relative
        origin = 'artifact'
      })
    }
  } finally {
    $zip.Dispose()
  }
  if ($rows.Count -eq 0) {
    throw "MIR 4 supply-chain archive has no files: $Path"
  }
  return $rows.ToArray()
}

function Get-MIR4SupplyChainIdentitySet {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string[]]$Paths
  )

  $rows = @(Get-MIR4SupplyChainExplicitRows -RepoRoot $RepoRoot -Paths $Paths)
  $root = Get-MIR4SupplyChainRowsRoot -Rows $rows
  return [pscustomobject][ordered]@{
    name = $Name
    root_sha256 = $root.sha256
    file_count = $root.file_count
    total_bytes = $root.total_bytes
    files = $rows
  }
}

function Test-MIR4SupplyChainMapKey {
  param(
    [AllowNull()][Collections.IDictionary]$Map,
    [Parameter(Mandatory)][string]$Key
  )

  return $null -ne $Map -and $Map.Contains($Key)
}

