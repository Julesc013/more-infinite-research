if (-not (Get-Command ConvertTo-MIR4BootstrapCanonicalJson -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'BootstrapMaterialization.ps1')
}

$script:MIR4SupplyChainAuthorityPath = '.mir/releases/governance/mir4/supply-chain.json'
$script:MIR4SupplyChainAuthoritySchemaPath = 'spec/schemas/mir4-supply-chain-authority-v1.schema.json'
$script:MIR4ComponentInventorySchemaPath = 'spec/schemas/mir4-component-inventory-v1.schema.json'
$script:MIR4SpdxProfileSchemaPath = 'spec/schemas/mir4-spdx-3.0.1-profile.schema.json'
$script:MIR4Spdx2ProfileSchemaPath = 'spec/schemas/mir4-spdx-2.3-compatibility.schema.json'
$script:MIR4SlsaProfileSchemaPath = 'spec/schemas/mir4-slsa-provenance-v1.schema.json'

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

function New-MIR4ComponentInventoryV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Collections.IDictionary]$ArtifactPaths = @{},
    [Collections.IDictionary]$ProvidedRowsByComponent = @{},
    [switch]$RequireClean
  )

  $repo = Resolve-MIR4SupplyChainRepoRoot -RepoRoot $RepoRoot
  $authority = Get-MIR4SupplyChainAuthority -RepoRoot $repo
  $source = Get-MIR4SupplyChainSourceIdentity -RepoRoot $repo
  if ($RequireClean -and -not [bool]$source.working_tree_clean) {
    throw '[mir4-supply-chain-clean-root-required]'
  }

  $cachedRepositoryRows = @(Get-MIR4SupplyChainRepositoryRows -RepoRoot $repo)
  $identitySets = [Collections.Generic.List[object]]::new()
  foreach ($property in $authority.identity_sets.PSObject.Properties) {
    $identityPaths = [string[]]@($property.Value | ForEach-Object { [string]$_ })
    $identityRows = @(Select-MIR4SupplyChainRows -Rows $cachedRepositoryRows -Paths $identityPaths)
    $identityRoot = Get-MIR4SupplyChainRowsRoot -Rows $identityRows
    $identitySets.Add([pscustomobject][ordered]@{
      name = $property.Name
      root_sha256 = $identityRoot.sha256
      file_count = $identityRoot.file_count
      total_bytes = $identityRoot.total_bytes
      files = $identityRows
    })
  }

  $cachedPackageRows = $null
  $components = [Collections.Generic.List[object]]::new()
  foreach ($component in $authority.components) {
    $componentId = [string]$component.component_id
    $materialization = 'source-closure'
    $artifact = $null
    if (Test-MIR4SupplyChainMapKey -Map $ProvidedRowsByComponent -Key $componentId) {
      $rows = @(
        $ProvidedRowsByComponent[$componentId] |
          ForEach-Object { ConvertTo-MIR4SupplyChainFileRow -Row $_ -Origin provided }
      )
      $materialization = 'provided-payload'
    } elseif (Test-MIR4SupplyChainMapKey -Map $ArtifactPaths -Key $componentId) {
      $artifactPath = Resolve-MIR4SupplyChainInputPath -RepoRoot $repo -Path ([string]$ArtifactPaths[$componentId])
      $rows = @(Get-MIR4SupplyChainArchiveRows -Path $artifactPath)
      $artifactItem = Get-Item -LiteralPath $artifactPath
      $artifact = [pscustomobject][ordered]@{
        name = [string]$component.inclusion.artifact_name
        bytes = [long]$artifactItem.Length
        sha256 = (Get-MIR4Sha256File -Path $artifactPath).ToUpperInvariant()
      }
      $materialization = 'artifact'
    } else {
      switch ([string]$component.source.selector) {
        'repository-tracked-source' {
          $rows = @($cachedRepositoryRows)
        }
        'player-package-source' {
          if ($null -eq $cachedPackageRows) {
            $cachedPackageRows = @(Select-MIR4SupplyChainRows -Rows $cachedRepositoryRows -Paths @(
              Get-MIRPackageSourceFiles -RepoRoot $repo
            ))
          }
          $rows = @($cachedPackageRows)
        }
        'explicit-files' {
          $explicitPaths = [string[]]@($component.source.paths | ForEach-Object { [string]$_ })
          $rows = @(Select-MIR4SupplyChainRows -Rows $cachedRepositoryRows -Paths $explicitPaths)
        }
        'preview-payload' {
          $previewPaths = @([string]$component.source_map.generator, $script:MIR4SupplyChainAuthorityPath, 'LICENSE') |
            Sort-Object -Unique -CaseSensitive
          $rows = @(Select-MIR4SupplyChainRows -Rows $cachedRepositoryRows -Paths $previewPaths)
        }
        default {
          throw "Unknown MIR 4 supply-chain selector: $($component.source.selector)"
        }
      }
    }
    if ($rows.Count -eq 0) {
      throw "MIR 4 supply-chain component is empty: $componentId"
    }
    $root = Get-MIR4SupplyChainRowsRoot -Rows $rows
    $components.Add([pscustomobject][ordered]@{
      component_id = $componentId
      name = [string]$component.name
      version = [string]$component.version
      artifact_class = [string]$component.artifact_class
      target = $component.target
      materialization = $materialization
      source_selector = [string]$component.source.selector
      source_map = $component.source_map
      license = $component.license
      copyright = $component.copyright
      redistribution_custody = $component.redistribution_custody
      capsule_partition = [string]$component.inclusion.release_capsule_partition
      artifact = $artifact
      content_root = $root
      files = @($rows | Sort-Object path -CaseSensitive)
    })
  }

  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4ComponentInventoryV1'
    programme_id = [string]$authority.programme_id
    turn = 'T15'
    state = 'pre-freeze-supply-chain-preparation'
    source = $source
    standards = $authority.standards
    construction = $authority.construction
    identity_sets = $identitySets.ToArray()
    components = $components.ToArray()
    transition_authority = [pscustomobject][ordered]@{
      source_freeze = $false
      candidate_allocation = $false
      production_signing = $false
      publication = $false
    }
    record_sha256 = $null
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

function Test-MIR4ComponentInventoryV1 {
  param(
    [Parameter(Mandatory)]$Inventory,
    [string]$RepoRoot
  )

  try {
    if ([int]$Inventory.schema -ne 1 -or
        [string]$Inventory.kind -cne 'MIR4ComponentInventoryV1' -or
        [string]$Inventory.turn -cne 'T15' -or
        @($Inventory.components).Count -ne 9 -or
        -not (Test-MIR4BootstrapRecordHash -Record $Inventory)) {
      return $false
    }
    $ids = @($Inventory.components | ForEach-Object { [string]$_.component_id })
    if (@($ids | Sort-Object -Unique -CaseSensitive).Count -ne 9) { return $false }
    foreach ($component in $Inventory.components) {
      $root = Get-MIR4SupplyChainRowsRoot -Rows @($component.files)
      if ([string]$root.sha256 -cne [string]$component.content_root.sha256 -or
          [int]$root.file_count -ne [int]$component.content_root.file_count -or
          [long]$root.total_bytes -ne [long]$component.content_root.total_bytes) {
        return $false
      }
    }
    foreach ($set in $Inventory.identity_sets) {
      $root = Get-MIR4SupplyChainRowsRoot -Rows @($set.files)
      if ([string]$root.sha256 -cne [string]$set.root_sha256) { return $false }
    }
    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
      $repo = Resolve-MIR4SupplyChainRepoRoot -RepoRoot $RepoRoot
      $raw = ConvertTo-MIR4BootstrapCanonicalJson -Value $Inventory
      if (-not ($raw | Test-Json -SchemaFile (Join-Path $repo $script:MIR4ComponentInventorySchemaPath) -ErrorAction Stop)) {
        return $false
      }
      $source = Get-MIR4SupplyChainSourceIdentity -RepoRoot $repo
      if ([string]$source.commit -cne [string]$Inventory.source.commit -or
          [string]$source.tree -cne [string]$Inventory.source.tree) {
        return $false
      }
    }
    return $true
  } catch {
    return $false
  }
}

function Get-MIR4SpdxElementToken {
  param([Parameter(Mandatory)][string]$Value)

  return (Get-MIR4Sha256String -Value $Value).Substring(0, 24).ToLowerInvariant()
}

function New-MIR4Spdx301Document {
  param(
    [Parameter(Mandatory)]$Inventory,
    [string]$ComponentId
  )

  if (-not (Test-MIR4ComponentInventoryV1 -Inventory $Inventory)) {
    throw '[mir4-spdx-inventory]'
  }
  $components = if ([string]::IsNullOrWhiteSpace($ComponentId)) {
    @($Inventory.components)
  } else {
    @($Inventory.components | Where-Object { [string]$_.component_id -ceq $ComponentId })
  }
  if ($components.Count -eq 0) {
    throw "Unknown MIR 4 SPDX component: $ComponentId"
  }

  $namespace = "https://more-infinite-research.invalid/spdx/3.0.1/$($Inventory.source.commit)/$($Inventory.record_sha256.ToLowerInvariant())"
  $creationId = '_:creationinfo'
  $toolId = "$namespace/agent/supply-chain"
  $documentId = "$namespace/document"
  $sbomId = "$namespace/sbom"
  $licenseId = "$namespace/license/mpl-2.0"
  $graph = [Collections.Generic.List[object]]::new()
  $documentElements = [Collections.Generic.List[string]]::new()
  $sbomElements = [Collections.Generic.List[string]]::new()
  $sbomRoots = [Collections.Generic.List[string]]::new()

  $graph.Add([pscustomobject][ordered]@{
    type = 'CreationInfo'
    '@id' = $creationId
    createdBy = @($toolId)
    specVersion = '3.0.1'
    created = [string]$Inventory.source.commit_time
  })
  $graph.Add([pscustomobject][ordered]@{
    type = 'Tool'
    spdxId = $toolId
    creationInfo = $creationId
    name = 'MIR4 SupplyChain.ps1'
  })
  $documentElements.Add($toolId)
  $graph.Add([pscustomobject][ordered]@{
    type = 'simplelicensing_LicenseExpression'
    spdxId = $licenseId
    creationInfo = $creationId
    simplelicensing_licenseExpression = 'MPL-2.0'
  })
  $documentElements.Add($licenseId)
  $documentElements.Add($sbomId)

  foreach ($component in $components) {
    $packageId = "$namespace/package/$($component.component_id)"
    $sbomRoots.Add($packageId)
    $sbomElements.Add($packageId)
    $documentElements.Add($packageId)
    $packageElement = [ordered]@{
      type = 'software_Package'
      spdxId = $packageId
      creationInfo = $creationId
      name = [string]$component.name
      software_packageVersion = [string]$component.version
      software_downloadLocation = 'https://github.com/Julesc013/more-infinite-research/releases'
      software_primaryPurpose = $(if ([string]$component.artifact_class -eq 'source-release') { 'source' } else { 'archive' })
      software_attributionText = @(
        "Declared license: MPL-2.0; preserve LICENSE. Copyright: NOASSERTION. MIR4 content root: sha256:$(([string]$component.content_root.sha256).ToLowerInvariant())."
      )
      software_copyrightText = 'NOASSERTION'
      verifiedUsing = @([pscustomobject][ordered]@{
        type = 'Hash'
        '@id' = "_:hash-$(Get-MIR4SpdxElementToken -Value $packageId)"
        algorithm = 'sha256'
        hashValue = $(if ($null -ne $component.artifact) {
          ([string]$component.artifact.sha256).ToLowerInvariant()
        } else {
          ([string]$component.content_root.sha256).ToLowerInvariant()
        })
      })
    }
    $graph.Add([pscustomobject]$packageElement)

    $fileIds = [Collections.Generic.List[string]]::new()
    foreach ($row in $component.files) {
      $fileId = "$namespace/file/$($component.component_id)/$(Get-MIR4SpdxElementToken -Value ([string]$row.path))"
      $fileIds.Add($fileId)
      $sbomElements.Add($fileId)
      $documentElements.Add($fileId)
      $graph.Add([pscustomobject][ordered]@{
        type = 'software_File'
        spdxId = $fileId
        creationInfo = $creationId
        name = [string]$row.path
        software_primaryPurpose = $(switch ([string]$row.source_class) {
          'binary-asset' { 'other' }
          'generated-projection' { 'evidence' }
          default { 'source' }
        })
        software_attributionText = @('Declared license: MPL-2.0; see LICENSE. Copyright: NOASSERTION.')
        software_copyrightText = 'NOASSERTION'
        verifiedUsing = @([pscustomobject][ordered]@{
          type = 'Hash'
          '@id' = "_:hash-$(Get-MIR4SpdxElementToken -Value $fileId)"
          algorithm = 'sha256'
          hashValue = ([string]$row.sha256).ToLowerInvariant()
        })
      })
    }

    $containsId = "$namespace/relationship/$($component.component_id)/contains"
    $licenseRelationshipId = "$namespace/relationship/$($component.component_id)/declared-license"
    $graph.Add([pscustomobject][ordered]@{
      type = 'Relationship'
      spdxId = $containsId
      creationInfo = $creationId
      from = $packageId
      relationshipType = 'contains'
      to = $fileIds.ToArray()
      completeness = 'complete'
    })
    $graph.Add([pscustomobject][ordered]@{
      type = 'Relationship'
      spdxId = $licenseRelationshipId
      creationInfo = $creationId
      from = $packageId
      relationshipType = 'hasDeclaredLicense'
      to = @($licenseId)
      completeness = 'complete'
    })
    $documentElements.Add($containsId)
    $documentElements.Add($licenseRelationshipId)
  }

  $graph.Insert(2, [pscustomobject][ordered]@{
    type = 'SpdxDocument'
    spdxId = $documentId
    creationInfo = $creationId
    rootElement = @($sbomId)
    element = $documentElements.ToArray()
    profileConformance = @('core', 'software', 'simpleLicensing')
  })
  $graph.Insert(3, [pscustomobject][ordered]@{
    type = 'software_Sbom'
    spdxId = $sbomId
    creationInfo = $creationId
    rootElement = $sbomRoots.ToArray()
    element = $sbomElements.ToArray()
    software_sbomType = @('build')
  })
  return [pscustomobject][ordered]@{
    '@context' = 'https://spdx.org/rdf/3.0.1/spdx-context.jsonld'
    '@graph' = $graph.ToArray()
  }
}

function New-MIR4Spdx23CompatibilityDocument {
  param(
    [Parameter(Mandatory)]$Inventory,
    [string]$ComponentId
  )

  if (-not (Test-MIR4ComponentInventoryV1 -Inventory $Inventory)) {
    throw '[mir4-spdx2-inventory]'
  }
  $components = if ([string]::IsNullOrWhiteSpace($ComponentId)) {
    @($Inventory.components)
  } else {
    @($Inventory.components | Where-Object { [string]$_.component_id -ceq $ComponentId })
  }
  if ($components.Count -eq 0) {
    throw "Unknown MIR 4 SPDX 2.3 component: $ComponentId"
  }
  $packages = [Collections.Generic.List[object]]::new()
  $files = [Collections.Generic.List[object]]::new()
  $relationships = [Collections.Generic.List[object]]::new()
  foreach ($component in $components) {
    $packageSpdxId = "SPDXRef-Package-$($component.component_id)"
    $package = [ordered]@{
      name = [string]$component.name
      SPDXID = $packageSpdxId
      versionInfo = [string]$component.version
      downloadLocation = 'NOASSERTION'
      filesAnalyzed = $true
      licenseConcluded = 'NOASSERTION'
      licenseDeclared = 'MPL-2.0'
      copyrightText = 'NOASSERTION'
      externalRefs = @([ordered]@{
        referenceCategory = 'OTHER'
        referenceType = 'mir4-content-root'
        referenceLocator = "sha256:$(([string]$component.content_root.sha256).ToLowerInvariant())"
      })
    }
    if ($null -ne $component.artifact) {
      $package['packageFileName'] = [string]$component.artifact.name
      $package['checksums'] = @([ordered]@{
        algorithm = 'SHA256'
        checksumValue = ([string]$component.artifact.sha256).ToLowerInvariant()
      })
    }
    $packages.Add([pscustomobject]$package)
    $relationships.Add([pscustomobject][ordered]@{
      spdxElementId = 'SPDXRef-DOCUMENT'
      relationshipType = 'DESCRIBES'
      relatedSpdxElement = $packageSpdxId
    })
    foreach ($row in $component.files) {
      $fileSpdxId = "SPDXRef-File-$($component.component_id)-$(Get-MIR4SpdxElementToken -Value ([string]$row.path))"
      $files.Add([pscustomobject][ordered]@{
        fileName = "./$([string]$row.path)"
        SPDXID = $fileSpdxId
        checksums = @([ordered]@{
          algorithm = 'SHA256'
          checksumValue = ([string]$row.sha256).ToLowerInvariant()
        })
        licenseConcluded = 'NOASSERTION'
        licenseInfoInFiles = @('NOASSERTION')
        copyrightText = 'NOASSERTION'
      })
      $relationships.Add([pscustomobject][ordered]@{
        spdxElementId = $packageSpdxId
        relationshipType = 'CONTAINS'
        relatedSpdxElement = $fileSpdxId
      })
    }
  }
  return [pscustomobject][ordered]@{
    spdxVersion = 'SPDX-2.3'
    dataLicense = 'CC0-1.0'
    SPDXID = 'SPDXRef-DOCUMENT'
    name = 'More Infinite Research 4 compatibility SBOM'
    documentNamespace = "https://more-infinite-research.invalid/spdx/2.3/$($Inventory.source.commit)/$($Inventory.record_sha256.ToLowerInvariant())"
    creationInfo = [pscustomobject][ordered]@{
      created = [string]$Inventory.source.commit_time
      creators = @('Tool: MIR4 SupplyChain.ps1')
    }
    documentDescribes = @($packages | ForEach-Object { [string]$_.SPDXID })
    packages = $packages.ToArray()
    files = $files.ToArray()
    relationships = $relationships.ToArray()
  }
}

function New-MIR4SlsaProvenanceV1 {
  param(
    [Parameter(Mandatory)]$Inventory,
    [string]$ComponentId
  )

  if (-not (Test-MIR4ComponentInventoryV1 -Inventory $Inventory)) {
    throw '[mir4-slsa-inventory]'
  }
  $components = if ([string]::IsNullOrWhiteSpace($ComponentId)) {
    @($Inventory.components)
  } else {
    @($Inventory.components | Where-Object { [string]$_.component_id -ceq $ComponentId })
  }
  if ($components.Count -eq 0) {
    throw "Unknown MIR 4 SLSA component: $ComponentId"
  }
  $subjects = @(
    foreach ($component in $components) {
      $sha256 = if ($null -ne $component.artifact) {
        [string]$component.artifact.sha256
      } else {
        [string]$component.content_root.sha256
      }
      [pscustomobject][ordered]@{
        name = [string]$component.component_id
        digest = [pscustomobject][ordered]@{ sha256 = $sha256.ToLowerInvariant() }
      }
    }
  )
  $resolved = [Collections.Generic.List[object]]::new()
  $resolved.Add([pscustomobject][ordered]@{
    uri = "git+https://github.com/Julesc013/more-infinite-research@$($Inventory.source.commit)"
    digest = [pscustomobject][ordered]@{
      gitCommit = [string]$Inventory.source.commit
      gitTree = [string]$Inventory.source.tree
    }
  })
  foreach ($set in $Inventory.identity_sets) {
    $resolved.Add([pscustomobject][ordered]@{
      uri = "urn:mir4:identity-set:$($set.name)"
      digest = [pscustomobject][ordered]@{
        sha256 = ([string]$set.root_sha256).ToLowerInvariant()
      }
    })
  }
  return [pscustomobject][ordered]@{
    '_type' = 'https://in-toto.io/Statement/v1'
    subject = $subjects
    predicateType = 'https://slsa.dev/provenance/v1'
    predicate = [pscustomobject][ordered]@{
      buildDefinition = [pscustomobject][ordered]@{
        buildType = 'https://more-infinite-research.invalid/build-types/supply-chain-v1'
        externalParameters = [pscustomobject][ordered]@{
          programme_id = [string]$Inventory.programme_id
          turn = 'T15'
          state = [string]$Inventory.state
          component_ids = @($components | ForEach-Object { [string]$_.component_id })
        }
        internalParameters = [pscustomobject][ordered]@{
          network = 'disabled'
          source_date_epoch = [long]$Inventory.source.source_date_epoch
          archive_order = [string]$Inventory.construction.archive_order
          archive_timestamp = [string]$Inventory.construction.archive_timestamp
          working_tree_clean = [bool]$Inventory.source.working_tree_clean
        }
        resolvedDependencies = $resolved.ToArray()
      }
      runDetails = [pscustomobject][ordered]@{
        builder = [pscustomobject][ordered]@{
          id = 'https://github.com/Julesc013/more-infinite-research/tools/lib/mir4/SupplyChain.ps1'
          builderDependencies = @([pscustomobject][ordered]@{
            uri = 'urn:mir4:canonicalization:MIR4BootstrapCanonicalJsonV1'
            digest = [pscustomobject][ordered]@{
              sha256 = ([string]$Inventory.identity_sets[0].root_sha256).ToLowerInvariant()
            }
          })
          version = [pscustomobject][ordered]@{ SupplyChain = '1' }
        }
        metadata = [pscustomobject][ordered]@{
          invocationId = "urn:mir4:t15:$($Inventory.record_sha256.ToLowerInvariant())"
          startedOn = [string]$Inventory.source.commit_time
          finishedOn = [string]$Inventory.source.commit_time
        }
        byproducts = @([pscustomobject][ordered]@{
          name = 'component-inventory.json'
          digest = [pscustomobject][ordered]@{
            sha256 = ([string]$Inventory.record_sha256).ToLowerInvariant()
          }
        })
      }
    }
  }
}

function Test-MIR4Spdx301Document {
  param(
    [Parameter(Mandatory)]$Document,
    [Parameter(Mandatory)]$Inventory,
    [string]$RepoRoot,
    [string]$OfficialSchemaPath
  )

  try {
    if ([string]$Document.'@context' -cne 'https://spdx.org/rdf/3.0.1/spdx-context.jsonld') {
      return $false
    }
    $graph = @($Document.'@graph')
    if (@($graph | Where-Object { [string]$_.type -ceq 'SpdxDocument' }).Count -ne 1 -or
        @($graph | Where-Object { [string]$_.type -ceq 'software_Sbom' }).Count -ne 1 -or
        @($graph | Where-Object { [string]$_.type -ceq 'software_Package' }).Count -eq 0 -or
        @($graph | Where-Object { [string]$_.type -ceq 'software_File' }).Count -eq 0) {
      return $false
    }
    $allowedTypes = @(
      'CreationInfo',
      'Tool',
      'SpdxDocument',
      'software_Sbom',
      'simplelicensing_LicenseExpression',
      'software_Package',
      'software_File',
      'Relationship'
    )
    if (@($graph | Where-Object { [string]$_.type -cnotin $allowedTypes }).Count -ne 0) {
      return $false
    }
    $elementIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($element in $graph) {
      $id = if ($element.PSObject.Properties['spdxId']) {
        [string]$element.spdxId
      } else {
        [string]$element.'@id'
      }
      if ([string]::IsNullOrWhiteSpace($id) -or -not $elementIds.Add($id)) {
        return $false
      }
      switch ([string]$element.type) {
        'CreationInfo' {
          if ($id -cnotmatch '^_:[a-z0-9-]+$' -or
              [string]$element.specVersion -cne '3.0.1' -or
              [string]$element.created -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or
              @($element.createdBy).Count -ne 1) {
            return $false
          }
        }
        'Tool' {
          if ([string]$element.name -cne 'MIR4 SupplyChain.ps1') { return $false }
        }
        'SpdxDocument' {
          if (@($element.rootElement).Count -ne 1 -or
              @($element.profileConformance | Sort-Object -CaseSensitive) -join '|' -cne 'core|simpleLicensing|software') {
            return $false
          }
        }
        'software_Sbom' {
          if (@($element.rootElement).Count -eq 0 -or
              @($element.software_sbomType).Count -ne 1 -or
              [string]$element.software_sbomType[0] -cne 'build') {
            return $false
          }
        }
        'simplelicensing_LicenseExpression' {
          if ([string]$element.simplelicensing_licenseExpression -cne 'MPL-2.0') { return $false }
        }
        'software_Package' {
          if ([string]$element.software_copyrightText -cne 'NOASSERTION' -or
              @($element.software_attributionText).Count -ne 1) {
            return $false
          }
        }
        'software_File' {
          Assert-MIR4SupplyChainRelativePath -Path ([string]$element.name)
          if ([string]$element.software_copyrightText -cne 'NOASSERTION' -or
              @($element.software_attributionText).Count -ne 1) {
            return $false
          }
        }
        'Relationship' {
          if ([string]$element.relationshipType -cnotin @('contains', 'hasDeclaredLicense') -or
              [string]$element.completeness -cne 'complete' -or
              @($element.to).Count -eq 0) {
            return $false
          }
        }
      }
      if ([string]$element.type -ne 'CreationInfo' -and
          [string]$element.creationInfo -cne '_:creationinfo') {
        return $false
      }
    }
    foreach ($element in $graph) {
      if (-not $element.PSObject.Properties['verifiedUsing']) { continue }
      foreach ($hash in @($element.verifiedUsing)) {
        if ([string]$hash.type -cne 'Hash' -or
            [string]$hash.algorithm -cne 'sha256' -or
            [string]$hash.hashValue -cnotmatch '^[a-f0-9]{64}$') {
          return $false
        }
      }
    }
    $raw = ConvertTo-MIR4BootstrapCanonicalJson -Value $Document
    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
      if (-not ($raw | Test-Json -SchemaFile (Join-Path $RepoRoot $script:MIR4SpdxProfileSchemaPath) -ErrorAction Stop)) {
        return $false
      }
    }
    if (-not [string]::IsNullOrWhiteSpace($OfficialSchemaPath)) {
      $officialHash = (Get-MIR4Sha256File -Path $OfficialSchemaPath).ToUpperInvariant()
      if ($officialHash -cne [string]$Inventory.standards.primary_sbom.official_schema_sha256) {
        return $false
      }
      # PowerShell's Test-Json expands the official SPDX anyOf closure once per
      # graph element. A whole-project graph can consume the host's entire RAM.
      # Validate one generator-complete component against the exact official
      # schema, then validate every full-graph element above with the same
      # closed generator profile.
      $representativeId = [string](@(
        $Inventory.components |
          Sort-Object { @($_.files).Count }, component_id |
          Select-Object -First 1
      )[0].component_id)
      $representative = New-MIR4Spdx301Document -Inventory $Inventory -ComponentId $representativeId
      $representativeRaw = ConvertTo-MIR4BootstrapCanonicalJson -Value $representative
      if (-not ($representativeRaw | Test-Json -SchemaFile $OfficialSchemaPath -ErrorAction Stop)) {
        return $false
      }
    }
    return $true
  } catch {
    return $false
  }
}

function Test-MIR4Spdx23CompatibilityDocument {
  param(
    [Parameter(Mandatory)]$Document,
    [Parameter(Mandatory)][string]$RepoRoot
  )

  try {
    $raw = ConvertTo-MIR4BootstrapCanonicalJson -Value $Document
    return [string]$Document.spdxVersion -ceq 'SPDX-2.3' -and
      [string]$Document.dataLicense -ceq 'CC0-1.0' -and
      ($raw | Test-Json -SchemaFile (Join-Path $RepoRoot $script:MIR4Spdx2ProfileSchemaPath) -ErrorAction Stop)
  } catch {
    return $false
  }
}

function Test-MIR4SlsaProvenanceV1 {
  param(
    [Parameter(Mandatory)]$Statement,
    [Parameter(Mandatory)][string]$RepoRoot
  )

  try {
    if ([string]$Statement.'_type' -cne 'https://in-toto.io/Statement/v1' -or
        [string]$Statement.predicateType -cne 'https://slsa.dev/provenance/v1' -or
        [string]$Statement.predicate.buildDefinition.internalParameters.network -cne 'disabled' -or
        @($Statement.subject).Count -eq 0) {
      return $false
    }
    $raw = ConvertTo-MIR4BootstrapCanonicalJson -Value $Statement
    return ($raw | Test-Json -SchemaFile (Join-Path $RepoRoot $script:MIR4SlsaProfileSchemaPath) -ErrorAction Stop)
  } catch {
    return $false
  }
}

function Write-MIR4SupplyChainRecord {
  param(
    [Parameter(Mandatory)]$Record,
    [Parameter(Mandatory)][string]$Path
  )

  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  [IO.File]::WriteAllText(
    $Path,
    (ConvertTo-MIR4BootstrapCanonicalJson -Value $Record) + [char]10,
    [Text.UTF8Encoding]::new($false)
  )
}
