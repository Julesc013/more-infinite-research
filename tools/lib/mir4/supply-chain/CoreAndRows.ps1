function Resolve-MIR4SupplyChainRepoRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $resolved = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not (Test-Path -LiteralPath (Join-Path $resolved '.git'))) {
    throw "MIR 4 supply-chain root is not a Git worktree: $resolved"
  }
  return $resolved
}

function Resolve-MIR4SupplyChainInputPath {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Path
  )

  $repo = Resolve-MIR4SupplyChainRepoRoot -RepoRoot $RepoRoot
  $candidate = if ([IO.Path]::IsPathRooted($Path)) {
    [IO.Path]::GetFullPath($Path)
  } else {
    [IO.Path]::GetFullPath((Join-Path $repo $Path))
  }
  return (Resolve-Path -LiteralPath $candidate).Path
}

function Assert-MIR4SupplyChainRelativePath {
  param([Parameter(Mandatory)][string]$Path)

  Assert-MIR4PortableArchivePath -Path $Path
  if ($Path.EndsWith('/')) {
    throw "MIR 4 supply-chain file paths cannot be directories: $Path"
  }
}

function Get-MIR4SupplyChainAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = Resolve-MIR4SupplyChainRepoRoot -RepoRoot $RepoRoot
  $raw = [IO.File]::ReadAllText((Join-Path $repo $script:MIR4SupplyChainAuthorityPath))
  if (-not ($raw | Test-Json -SchemaFile (Join-Path $repo $script:MIR4SupplyChainAuthoritySchemaPath) -ErrorAction Stop)) {
    throw '[mir4-supply-chain-authority-schema]'
  }
  $authority = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  if ([bool]$authority.package_visible -or
      @($authority.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0 -or
      [bool]$authority.attestation.production_key_generation_authorized) {
    throw '[mir4-supply-chain-authority-firewall]'
  }
  return $authority
}

function Get-MIR4SupplyChainGitValue {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string[]]$Arguments
  )

  $value = & git -C $RepoRoot @Arguments 2>$null
  if ($LASTEXITCODE -ne 0 -or $null -eq $value) {
    throw "Unable to resolve MIR 4 Git identity: git $($Arguments -join ' ')"
  }
  return ([string](@($value) -join [char]10)).Trim()
}

function Get-MIR4SupplyChainSourceIdentity {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = Resolve-MIR4SupplyChainRepoRoot -RepoRoot $RepoRoot
  $commit = Get-MIR4SupplyChainGitValue -RepoRoot $repo -Arguments @('rev-parse', 'HEAD')
  $tree = Get-MIR4SupplyChainGitValue -RepoRoot $repo -Arguments @('rev-parse', 'HEAD^{tree}')
  $epochText = Get-MIR4SupplyChainGitValue -RepoRoot $repo -Arguments @('show', '-s', '--format=%ct', 'HEAD')
  [long]$epoch = 0
  if (-not [long]::TryParse($epochText, [ref]$epoch) -or $epoch -le 0) {
    throw '[mir4-supply-chain-source-epoch]'
  }
  $commitTime = [DateTimeOffset]::FromUnixTimeSeconds($epoch).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
  $status = @(& git -C $repo status --porcelain=v1 --untracked-files=all 2>$null)
  if ($LASTEXITCODE -ne 0) { throw '[mir4-supply-chain-source-status]' }
  return [pscustomobject][ordered]@{
    repository = 'https://github.com/Julesc013/more-infinite-research'
    commit = $commit.ToLowerInvariant()
    tree = $tree.ToLowerInvariant()
    commit_time = $commitTime
    source_date_epoch = $epoch
    working_tree_clean = ($status.Count -eq 0)
  }
}

function Get-MIR4SupplyChainFileClass {
  param([Parameter(Mandatory)][string]$Path)

  $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  if ($extension -in @('.png', '.jpg', '.jpeg', '.gif', '.ico', '.zip', '.7z', '.pdf', '.exe', '.dll', '.pdb', '.bin')) {
    return 'binary-asset'
  }
  if ($Path -match '^(?:docs/reference/generated|dist|build)/' -or
      $Path -match '(?:^|/)(?:generated|projections?)(?:/|\.)') {
    return 'generated-projection'
  }
  return 'manual-source'
}

function Get-MIR4SupplyChainFileRow {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$RelativePath,
    [ValidateSet('repository', 'artifact', 'provided')][string]$Origin = 'repository'
  )

  $relative = $RelativePath.Replace('\', '/')
  Assert-MIR4SupplyChainRelativePath -Path $relative
  $full = Assert-MIR4DescendantPath -Root $Root -Path (Join-Path $Root $relative)
  $null = Assert-MIR4NoReparseAncestors -Root $Root -Path $full
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
    throw "MIR 4 supply-chain source file is absent: $relative"
  }
  $item = Get-Item -LiteralPath $full -Force
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "MIR 4 supply-chain source files cannot be reparse points: $relative"
  }
  return [pscustomobject][ordered]@{
    path = $relative
    bytes = [long]$item.Length
    sha256 = (Get-MIR4Sha256File -Path $full).ToUpperInvariant()
    source_class = Get-MIR4SupplyChainFileClass -Path $relative
    origin = $Origin
  }
}

function ConvertTo-MIR4SupplyChainFileRow {
  param(
    [Parameter(Mandatory)]$Row,
    [ValidateSet('repository', 'artifact', 'provided')][string]$Origin = 'provided'
  )

  $path = ([string]$Row.path).Replace('\', '/')
  Assert-MIR4SupplyChainRelativePath -Path $path
  [long]$bytes = [long]$Row.bytes
  $sha256 = ([string]$Row.sha256).ToUpperInvariant()
  if ($bytes -lt 0 -or $sha256 -cnotmatch '^[A-F0-9]{64}$') {
    throw "Invalid MIR 4 supply-chain file identity: $path"
  }
  $class = if ($Row.PSObject.Properties['source_class']) {
    [string]$Row.source_class
  } else {
    Get-MIR4SupplyChainFileClass -Path $path
  }
  if ($class -notin @('manual-source', 'generated-projection', 'binary-asset', 'archive-metadata')) {
    throw "Invalid MIR 4 supply-chain source class: $class"
  }
  return [pscustomobject][ordered]@{
    path = $path
    bytes = $bytes
    sha256 = $sha256
    source_class = $class
    origin = $Origin
  }
}

function Get-MIR4SupplyChainRowsRoot {
  param([Parameter(Mandatory)][object[]]$Rows)

  $incremental = [Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
  [long]$total = 0
  $count = 0
  $previous = $null
  try {
    foreach ($row in @($Rows | Sort-Object path -CaseSensitive)) {
      $path = [string]$row.path
      Assert-MIR4SupplyChainRelativePath -Path $path
      if ($null -ne $previous -and [StringComparer]::OrdinalIgnoreCase.Equals($previous, $path)) {
        throw "Duplicate or ordinal-case-colliding MIR 4 inventory path: $previous and $path"
      }
      $previous = $path
      [long]$bytes = [long]$row.bytes
      $sha256 = ([string]$row.sha256).ToUpperInvariant()
      if ($bytes -lt 0 -or $sha256 -cnotmatch '^[A-F0-9]{64}$') {
        throw "Invalid MIR 4 inventory row: $path"
      }
      $line = $path + [char]9 + $bytes + [char]9 + $sha256 + [char]10
      $material = [Text.UTF8Encoding]::new($false).GetBytes($line)
      $incremental.AppendData($material)
      $total += $bytes
      $count++
    }
    return [pscustomobject][ordered]@{
      algorithm = 'SHA-256'
      mode = 'ordinal-path-byte-root-v1'
      sha256 = ([BitConverter]::ToString($incremental.GetHashAndReset())).Replace('-', '')
      file_count = $count
      total_bytes = $total
    }
  } finally {
    $incremental.Dispose()
  }
}

