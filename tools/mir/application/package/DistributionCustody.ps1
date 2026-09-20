Set-StrictMode -Version Latest

function Get-MIR4DistributionCustodyRepoRoot {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Get-MIR4DistributionCustodySharedRepoRoot {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4DistributionCustodyRepoRoot -RepoRoot $RepoRoot
  $commonGitDirectory = @(& git -C $repo rev-parse --path-format=absolute --git-common-dir 2>$null)
  if ($LASTEXITCODE -ne 0 -or $commonGitDirectory.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$commonGitDirectory[0])) {
    throw '[mir4-distribution-custody-git-common-directory]'
  }
  $commonGitDirectory = [IO.Path]::GetFullPath(([string]$commonGitDirectory[0]).Trim())

  $configuredPrimaryWorktree = @(& git -C $repo config --path --get core.worktree 2>$null)
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1) {
    throw '[mir4-distribution-custody-primary-worktree-config]'
  }
  if ($configuredPrimaryWorktree.Count -gt 1) {
    throw '[mir4-distribution-custody-primary-worktree-ambiguous]'
  }
  $configuredPrimaryWorktree = if ($configuredPrimaryWorktree.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace([string]$configuredPrimaryWorktree[0])) {
    [IO.Path]::GetFullPath(([string]$configuredPrimaryWorktree[0]).Trim())
  }
  else { $null }

  $worktreeLines = @(& git -C $repo worktree list --porcelain 2>$null)
  if ($LASTEXITCODE -ne 0) { throw '[mir4-distribution-custody-worktree-list]' }
  $primaryLine = @($worktreeLines | Where-Object { $_.StartsWith('worktree ', [StringComparison]::Ordinal) } | Select-Object -First 1)
  if ($primaryLine.Count -ne 1) { throw '[mir4-distribution-custody-primary-worktree-missing]' }
  $primary = [IO.Path]::GetFullPath(([string]$primaryLine[0]).Substring(9))
  if ($primary.Equals($commonGitDirectory, [StringComparison]::OrdinalIgnoreCase)) {
    if ($null -eq $configuredPrimaryWorktree) { throw '[mir4-distribution-custody-primary-worktree-unresolved]' }
    $primary = $configuredPrimaryWorktree
  }
  if (-not (Test-Path -LiteralPath $primary -PathType Container)) {
    throw '[mir4-distribution-custody-primary-worktree-unavailable]'
  }
  $primaryCommonGitDirectory = @(& git -C $primary rev-parse --path-format=absolute --git-common-dir 2>$null)
  if ($LASTEXITCODE -ne 0 -or
      $primaryCommonGitDirectory.Count -ne 1 -or
      -not ([IO.Path]::GetFullPath(([string]$primaryCommonGitDirectory[0]).Trim()).Equals($commonGitDirectory, [StringComparison]::OrdinalIgnoreCase))) {
    throw '[mir4-distribution-custody-primary-worktree-mismatch]'
  }
  return $primary
}

function Get-MIR4DistributionCustodyManifest {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4DistributionCustodyRepoRoot -RepoRoot $RepoRoot
  $path = Join-Path $repo '.mir/distributions.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw '[mir4-distribution-custody-manifest-missing]' }
  $manifest = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100 -DateKind String
  if ([int]$manifest.schema -ne 1 -or
      [string]$manifest.status -cne 'ignored-local-distribution-inventory' -or
      [int]$manifest.distribution_count -ne @($manifest.distributions).Count) {
    throw '[mir4-distribution-custody-manifest-shape]'
  }
  $custody = $manifest.custody
  if ([string]$custody.kind -cne 'git-pinned-predecessor-archive-custody-v1' -or
      [string]$custody.predecessor_commit -notmatch '^[0-9A-Fa-f]{40}$' -or
      [string]$custody.predecessor_tree -notmatch '^[0-9A-Fa-f]{40}$' -or
      [string]$custody.archive_root -cne 'dist' -or
      [bool]$custody.history_rewritten -or
      [bool]$custody.network_retrieval_permitted -or
      [bool]$custody.working_tree_archives_tracked) {
    throw '[mir4-distribution-custody-policy]'
  }
  $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($distribution in @($manifest.distributions)) {
    $relativePath = [string]$distribution.path
    if ($relativePath -notmatch '^dist/more-infinite-research_[0-9]+(?:[.][0-9]+)+[.]zip$' -or
        -not $paths.Add($relativePath) -or
        [string]$distribution.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
        [int64]$distribution.bytes -lt 1) {
      throw "[mir4-distribution-custody-distribution] $relativePath"
    }
  }
  return $manifest
}

function Get-MIR4DistributionCustodyCacheRoot {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[string]$CacheRoot)
  $repo = Get-MIR4DistributionCustodyRepoRoot -RepoRoot $RepoRoot
  if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$env:MIR_CACHE_HOME)) {
      $CacheRoot = Join-Path $env:MIR_CACHE_HOME 'distributions'
    }
    else {
      $sharedRepo = Get-MIR4DistributionCustodySharedRepoRoot -RepoRoot $repo
      $CacheRoot = Join-Path $sharedRepo 'build/cache/mir-distributions'
    }
  }
  if (-not [IO.Path]::IsPathRooted($CacheRoot)) { $CacheRoot = Join-Path $repo $CacheRoot }
  return [IO.Path]::GetFullPath($CacheRoot)
}

function Resolve-MIR4DistributionCustodyOutputRoot {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$OutputRoot)
  $repo = Get-MIR4DistributionCustodyRepoRoot -RepoRoot $RepoRoot
  if (-not [IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot = Join-Path $repo $OutputRoot }
  $resolved = [IO.Path]::GetFullPath($OutputRoot)
  $allowedRoots = @(
    [IO.Path]::GetFullPath((Join-Path $repo 'dist')),
    [IO.Path]::GetFullPath((Join-Path $repo 'build'))
  )
  foreach ($allowed in $allowedRoots) {
    if ($resolved -ceq $allowed -or $resolved.StartsWith($allowed + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
      $relative = $resolved.Substring($repo.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
      $cursor = $repo
      foreach ($component in @($relative -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($component)) { continue }
        $cursor = Join-Path $cursor $component
        if (-not (Test-Path -LiteralPath $cursor)) { continue }
        $item = Get-Item -LiteralPath $cursor -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
          throw "[mir4-distribution-custody-output-reparse] $cursor"
        }
      }
      return $resolved
    }
  }
  throw '[mir4-distribution-custody-output-root] output must be beneath the repository dist or build root.'
}

function Get-MIR4DistributionCustodyEntry {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Version)
  $manifest = Get-MIR4DistributionCustodyManifest -RepoRoot $RepoRoot
  $matches = @($manifest.distributions | Where-Object { [string]$_.version -ceq $Version })
  if ($matches.Count -ne 1) { throw "[mir4-distribution-custody-version] $Version" }
  return $matches[0]
}

function Test-MIR4DistributionCustodyFile {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Distribution)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $file = Get-Item -LiteralPath $Path -Force
  if ($file.Length -ne [int64]$Distribution.bytes) { return $false }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ceq [string]$Distribution.sha256
}

function Get-MIR4DistributionGitBlobSha256 {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$GitSpec)
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = 'git'
  $null = $startInfo.ArgumentList.Add('-C')
  $null = $startInfo.ArgumentList.Add($RepoRoot)
  $null = $startInfo.ArgumentList.Add('cat-file')
  $null = $startInfo.ArgumentList.Add('blob')
  $null = $startInfo.ArgumentList.Add($GitSpec)
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw '[mir4-distribution-custody-git-start]' }
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $digest = $sha.ComputeHash($process.StandardOutput.BaseStream)
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "[mir4-distribution-custody-git-blob] $stderr" }
    return [BitConverter]::ToString($digest).Replace('-', '')
  }
  finally {
    $sha.Dispose()
    $process.Dispose()
  }
}

function Test-MIR4DistributionHistoricalCustody {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Distribution)
  $repo = Get-MIR4DistributionCustodyRepoRoot -RepoRoot $RepoRoot
  $manifest = Get-MIR4DistributionCustodyManifest -RepoRoot $repo
  $commit = [string]$manifest.custody.predecessor_commit
  $relativePath = [string]$Distribution.path
  $resolvedCommit = @(& git -C $repo rev-parse "$commit^{commit}" 2>$null)
  if ($LASTEXITCODE -ne 0 -or $resolvedCommit.Count -ne 1 -or [string]$resolvedCommit[0] -cne $commit.ToLowerInvariant()) {
    throw "[mir4-distribution-custody-commit] $commit"
  }
  $resolvedTree = @(& git -C $repo rev-parse "$commit^{tree}" 2>$null)
  if ($LASTEXITCODE -ne 0 -or $resolvedTree.Count -ne 1 -or [string]$resolvedTree[0] -cne ([string]$manifest.custody.predecessor_tree).ToLowerInvariant()) {
    throw '[mir4-distribution-custody-tree]'
  }
  & git -C $repo cat-file -e "$commit`:$relativePath" 2>$null
  if ($LASTEXITCODE -ne 0) { throw "[mir4-distribution-custody-blob] $relativePath" }
  $size = @(& git -C $repo cat-file -s "$commit`:$relativePath" 2>$null)
  if ($LASTEXITCODE -ne 0 -or $size.Count -ne 1 -or [int64]$size[0] -ne [int64]$Distribution.bytes) {
    throw "[mir4-distribution-custody-bytes] $relativePath"
  }
  $actualSha256 = Get-MIR4DistributionGitBlobSha256 -RepoRoot $repo -GitSpec "$commit`:$relativePath"
  if ($actualSha256 -cne ([string]$Distribution.sha256).ToUpperInvariant()) {
    throw "[mir4-distribution-custody-sha256] $relativePath"
  }
  return [pscustomobject][ordered]@{
    version=[string]$Distribution.version
    path=$relativePath
    commit=$commit.ToUpperInvariant()
    tree=([string]$manifest.custody.predecessor_tree).ToUpperInvariant()
    bytes=[int64]$Distribution.bytes
    sha256=[string]$Distribution.sha256
    object_state='present-hash-verified'
  }
}

function Copy-MIR4DistributionGitBlobToPath {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$GitSpec,[Parameter(Mandatory)][string]$DestinationPath)
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = 'git'
  $null = $startInfo.ArgumentList.Add('-C')
  $null = $startInfo.ArgumentList.Add($RepoRoot)
  $null = $startInfo.ArgumentList.Add('cat-file')
  $null = $startInfo.ArgumentList.Add('blob')
  $null = $startInfo.ArgumentList.Add($GitSpec)
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw '[mir4-distribution-custody-git-start]' }
  try {
    $destination = [IO.File]::Open($DestinationPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $process.StandardOutput.BaseStream.CopyTo($destination) }
    finally { $destination.Dispose() }
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "[mir4-distribution-custody-git-blob] $stderr" }
  }
  finally {
    $process.Dispose()
  }
}

function Restore-MIR4DistributionArchive {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Version,
    [string]$CacheRoot,
    [string]$OutputRoot
  )
  $repo = Get-MIR4DistributionCustodyRepoRoot -RepoRoot $RepoRoot
  $manifest = Get-MIR4DistributionCustodyManifest -RepoRoot $repo
  $distribution = Get-MIR4DistributionCustodyEntry -RepoRoot $repo -Version $Version
  $custody = Test-MIR4DistributionHistoricalCustody -RepoRoot $repo -Distribution $distribution
  $cache = Get-MIR4DistributionCustodyCacheRoot -RepoRoot $repo -CacheRoot $CacheRoot
  if (-not (Test-Path -LiteralPath $cache -PathType Container)) { New-Item -ItemType Directory -Path $cache -Force | Out-Null }
  $cachePath = Join-Path $cache (([string]$distribution.sha256).ToUpperInvariant() + '.zip')
  $cacheState = 'reused'
  if (-not (Test-MIR4DistributionCustodyFile -Path $cachePath -Distribution $distribution)) {
    if (Test-Path -LiteralPath $cachePath -PathType Leaf) { throw "[mir4-distribution-custody-cache-mismatch] $cachePath" }
    $temporary = Join-Path $cache ('.' + [IO.Path]::GetFileName($cachePath) + '.' + [Guid]::NewGuid().ToString('N') + '.partial')
    try {
      Copy-MIR4DistributionGitBlobToPath -RepoRoot $repo -GitSpec ("$($manifest.custody.predecessor_commit):$($distribution.path)") -DestinationPath $temporary
      if (-not (Test-MIR4DistributionCustodyFile -Path $temporary -Distribution $distribution)) { throw "[mir4-distribution-custody-restored-hash] $Version" }
      try { [IO.File]::Move($temporary, $cachePath) }
      catch {
        if (-not (Test-MIR4DistributionCustodyFile -Path $cachePath -Distribution $distribution)) { throw }
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
      }
      $cacheState = 'materialized-from-pinned-git-history'
    }
    finally {
      if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
  }
  $outputPath = $null
  $outputState = 'not-requested'
  if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) {
    $resolvedOutputRoot = Resolve-MIR4DistributionCustodyOutputRoot -RepoRoot $repo -OutputRoot $OutputRoot
    if (-not (Test-Path -LiteralPath $resolvedOutputRoot -PathType Container)) { New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null }
    $outputPath = Join-Path $resolvedOutputRoot ([IO.Path]::GetFileName([string]$distribution.path))
    if (Test-MIR4DistributionCustodyFile -Path $outputPath -Distribution $distribution) {
      $outputState = 'reused'
    }
    elseif (Test-Path -LiteralPath $outputPath -PathType Leaf) {
      throw "[mir4-distribution-custody-output-mismatch] $outputPath"
    }
    else {
      $temporary = Join-Path $resolvedOutputRoot ('.' + [IO.Path]::GetFileName($outputPath) + '.' + [Guid]::NewGuid().ToString('N') + '.partial')
      try {
        [IO.File]::Copy($cachePath, $temporary, $false)
        if (-not (Test-MIR4DistributionCustodyFile -Path $temporary -Distribution $distribution)) { throw "[mir4-distribution-custody-output-hash] $Version" }
        [IO.File]::Move($temporary, $outputPath)
        $outputState = 'materialized-from-verified-cache'
      }
      finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
      }
    }
  }
  return [pscustomobject][ordered]@{
    version=[string]$distribution.version
    path=[string]$distribution.path
    sha256=[string]$distribution.sha256
    bytes=[int64]$distribution.bytes
    custody=$custody
    cache_path=$cachePath
    cache_state=$cacheState
    output_path=$outputPath
    output_state=$outputState
    release_transition_authority=$false
    publication_authority=$false
  }
}
