Set-StrictMode -Version Latest

$mir42CandidateBuildRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42CandidateBuildRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Get-MIR4CanonicalPackageAuthority -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42CandidateBuildRoot 'tools/mir/application/package/PackageAuthority.ps1')
}
if (-not (Get-Command New-MIR4TargetPackage -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42CandidateBuildRoot 'tools/mir/application/package/TargetMaterializer.ps1')
}

function Assert-MIR42FourTargetCleanSnapshot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$ExpectedCommit,
    [Parameter(Mandatory)][string]$ExpectedTree,
    [Parameter(Mandatory)][string]$ExpectedPackageSourceSha256
  )

  $head = @(& git -C $RepoRoot rev-parse HEAD 2>$null)
  if ($LASTEXITCODE -ne 0 -or $head.Count -ne 1 -or
      -not [string]::Equals(([string]$head[0]).Trim(), $ExpectedCommit, [StringComparison]::OrdinalIgnoreCase)) {
    throw '[mir42-four-target-source-snapshot-commit]'
  }
  $tree = @(& git -C $RepoRoot rev-parse 'HEAD^{tree}' 2>$null)
  if ($LASTEXITCODE -ne 0 -or $tree.Count -ne 1 -or
      -not [string]::Equals(([string]$tree[0]).Trim(), $ExpectedTree, [StringComparison]::OrdinalIgnoreCase)) {
    throw '[mir42-four-target-source-snapshot-tree]'
  }
  $trackedStatus = @(& git -C $RepoRoot status --porcelain --untracked-files=no 2>$null)
  if ($LASTEXITCODE -ne 0) { throw '[mir42-four-target-source-snapshot-status]' }
  if ($trackedStatus.Count -ne 0) { throw '[mir42-four-target-source-snapshot-dirty]' }
  if ((Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot) -cne $ExpectedPackageSourceSha256) {
    throw '[mir42-four-target-source-snapshot-package-source]'
  }
}

function Resolve-MIR42FourTargetOutputRoot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$OutputRoot
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $buildRoot = Join-Path $repo 'build'
  $candidate = if ([IO.Path]::IsPathRooted($OutputRoot)) {
    [IO.Path]::GetFullPath($OutputRoot)
  } else {
    [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
  }
  $null = Assert-MIR4DescendantPath -Root $buildRoot -Path $candidate
  $null = Assert-MIR4NoReparseAncestors -Root $repo -Path $candidate
  return $candidate
}

function Assert-MIR42FourTargetOutputAdmission {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$OutputRoot)

  if (Test-Path -LiteralPath $OutputRoot -PathType Leaf) {
    throw '[mir42-four-target-output-root-file]'
  }
  if (Test-Path -LiteralPath $OutputRoot -PathType Container) {
    if (@(Get-ChildItem -LiteralPath $OutputRoot -Force).Count -ne 0) {
      throw '[mir42-four-target-output-root-not-empty]'
    }
  } else {
    New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
  }

  $probe = Join-Path $OutputRoot ('.mir42-write-probe-' + [guid]::NewGuid().ToString('N'))
  try {
    [IO.File]::WriteAllText($probe, 'mir42-output-admission', [Text.UTF8Encoding]::new($false))
    if ([IO.File]::ReadAllText($probe) -cne 'mir42-output-admission') {
      throw '[mir42-four-target-output-write-readback]'
    }
  } finally {
    if (Test-Path -LiteralPath $probe -PathType Leaf) {
      Remove-Item -LiteralPath $probe -Force
    }
  }
}

function Get-MIR42FourTargetCapacityAdmission {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][Int64]$MinimumFreeMemoryBytes,
    [Parameter(Mandatory)][Int64]$MinimumFreeWorkBytes
  )

  try {
    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $freeMemory = [Int64]$operatingSystem.FreePhysicalMemory * 1KB
  } catch {
    throw '[mir42-four-target-capacity-memory-query]'
  }
  $driveRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($OutputRoot))
  try {
    $drive = [IO.DriveInfo]::new($driveRoot)
    $freeWork = [Int64]$drive.AvailableFreeSpace
  } catch {
    throw '[mir42-four-target-capacity-work-query]'
  }
  if ($freeMemory -lt $MinimumFreeMemoryBytes) { throw '[mir42-four-target-capacity-memory]' }
  if ($freeWork -lt $MinimumFreeWorkBytes) { throw '[mir42-four-target-capacity-work]' }
  return [pscustomobject][ordered]@{
    admitted = $true
    minimum_free_memory_bytes = $MinimumFreeMemoryBytes
    minimum_free_work_bytes = $MinimumFreeWorkBytes
  }
}

function Assert-MIR42FourTargetPackageSurface {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Inventory,
    [Parameter(Mandatory)][string]$ExpectedRoot,
    [Parameter(Mandatory)][string]$ExpectedVersion
  )

  if ([string]$Inventory.root -cne $ExpectedRoot) { throw '[mir42-four-target-package-root]' }
  $forbiddenPrefixes = @(
    '.codex/', '.github/', '.mir/', 'build/', 'dist/', 'docs/', 'evidence/', 'fixtures/', 'scripts/', 'tests/'
  )
  foreach ($entry in @($Inventory.entries)) {
    $relative = ([string]$entry.path).Replace('\', '/')
    $lower = $relative.ToLowerInvariant()
    if ($lower -ceq 'agents.md' -or
        @($forbiddenPrefixes | Where-Object { $lower.StartsWith($_, [StringComparison]::Ordinal) }).Count -ne 0) {
      throw "[mir42-four-target-package-excluded-surface] $relative"
    }
  }
  try {
    $info = Read-MIR4ArchiveText -Path ([string]$Inventory.path) -RelativePath 'info.json' | ConvertFrom-Json -Depth 20 -DateKind String
  } catch {
    throw '[mir42-four-target-package-info]'
  }
  if ([string]$info.version -cne $ExpectedVersion) { throw '[mir42-four-target-package-version]' }
}

function Get-MIR42FourTargetVerifiedMaterialization {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Materialization,
    [Parameter(Mandatory)][string]$ExpectedRoot,
    [Parameter(Mandatory)][string]$ExpectedVersion
  )

  $archivePath = [string]$Materialization.archive_path
  if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw '[mir42-four-target-materializer-archive-missing]'
  }
  $inventory = Get-MIR4ArchiveInventory -Path $archivePath
  $inventory | Add-Member -NotePropertyName path -NotePropertyValue $archivePath
  if ([string]$Materialization.archive_sha256 -cne [string]$inventory.archive_sha256 -or
      [string]$Materialization.content_sha256 -cne [string]$inventory.content_sha256 -or
      [int]$Materialization.entry_count -ne [int]$inventory.entry_count) {
    throw '[mir42-four-target-materializer-identity]'
  }
  Assert-MIR42FourTargetPackageSurface -Inventory $inventory -ExpectedRoot $ExpectedRoot -ExpectedVersion $ExpectedVersion
  return $inventory
}

function Write-MIR42FourTargetTargetRow {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)]$Row
  )

  $path = Resolve-MIR4ArtifactPath -OutputRoot $OutputRoot -RelativePath ("target-rows/$([string]$Row.target).json")
  Write-MIR4BootstrapRecord -Record $Row -Path $path | Out-Null
  return $path
}

function Write-MIR42FourTargetManifest {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)]$Preflight,
    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Failures
  )

  $complete = $Failures.Count -eq 0 -and $Rows.Count -eq 4
  $manifest = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42FourTargetDeterministicCandidateManifestV1'
    status = if ($complete) {
      'private-deterministic-four-target-candidate-built-unqualified'
    } else {
      'private-deterministic-four-target-candidate-partial'
    }
    build_complete = $complete
    source = $Preflight.source
    package_authority_sha256 = [string]$Preflight.package_authority_sha256
    package_source_sha256 = [string]$Preflight.package_source_sha256
    target_authority = @($Preflight.target_authority)
    resource_admission = $Preflight.resource_admission
    targets = @(
      foreach ($row in $Rows) {
        [pscustomobject][ordered]@{
          target = [string]$row.target
          distribution_version = [string]$row.distribution_version
          target_row_path = "target-rows/$([string]$row.target).json"
          asset = $row.asset
          content_sha256 = [string]$row.content_sha256
          entry_count = [int]$row.entry_count
        }
      }
    )
    failures = @($Failures)
    qualification = 'not-performed'
    technical_seal = 'not-performed'
    signing = 'not-performed'
    tagging = 'not-performed'
    publication_authorized = $false
    record_sha256 = ''
  }
  $path = Resolve-MIR4ArtifactPath -OutputRoot $OutputRoot -RelativePath 'candidate-manifest.json'
  Write-MIR4BootstrapRecord -Record $manifest -Path $path | Out-Null
  $schema = Join-Path $mir42CandidateBuildRoot 'spec/schemas/mir42-four-target-deterministic-candidate-manifest-v1.schema.json'
  if (-not (Get-Content -Raw -LiteralPath $path | Test-Json -SchemaFile $schema)) {
    throw '[mir42-four-target-deterministic-manifest-schema]'
  }
  return $manifest
}

function New-MIR42FourTargetCandidate {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$FinalSourceCommit,
    [Parameter(Mandatory)][ValidatePattern('^[A-Z0-9][A-Z0-9.-]{0,47}$')][string]$BuildId,
    [string]$OutputRoot,
    [ValidateRange(1, 9223372036854775807)][Int64]$MinimumFreeMemoryBytes = 1GB,
    [ValidateRange(1, 9223372036854775807)][Int64]$MinimumFreeWorkBytes = 2GB
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path 'build/mir42-four-target-candidates' $BuildId
  }
  $output = Resolve-MIR42FourTargetOutputRoot -RepoRoot $repo -OutputRoot $OutputRoot

  $head = @(& git -C $repo rev-parse HEAD 2>$null)
  $tree = @(& git -C $repo rev-parse 'HEAD^{tree}' 2>$null)
  if ($LASTEXITCODE -ne 0 -or $head.Count -ne 1 -or $tree.Count -ne 1) {
    throw '[mir42-four-target-source-snapshot-git]'
  }
  $headCommit = ([string]$head[0]).Trim()
  $headTree = ([string]$tree[0]).Trim()
  if (-not [string]::Equals($headCommit, $FinalSourceCommit, [StringComparison]::OrdinalIgnoreCase)) {
    throw '[mir42-four-target-final-source-commit]'
  }

  $packageAuthority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $targets = @('f210', 'f200', 'f110', 'f100')
  $authorityTargets = @($packageAuthority.targets | ForEach-Object { [string]$_.target })
  if ($authorityTargets.Count -ne 4 -or ($authorityTargets -join '|') -cne ($targets -join '|')) {
    throw '[mir42-four-target-authority-target-set]'
  }
  $identities = [ordered]@{}
  $expectedVersions = [ordered]@{ f210 = '4.2.21000'; f200 = '4.2.20000'; f110 = '4.2.11000'; f100 = '4.2.10000' }
  foreach ($target in $targets) {
    $identity = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $repo -Target $target -SourceVersion '4.2.0'
    if ([string]$identity.distribution_version -cne [string]$expectedVersions[$target]) {
      throw "[mir42-four-target-authority-version] $target"
    }
    $identities[$target] = $identity
  }
  $packageSourceSha256 = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
  Assert-MIR42FourTargetCleanSnapshot -RepoRoot $repo -ExpectedCommit $headCommit -ExpectedTree $headTree -ExpectedPackageSourceSha256 $packageSourceSha256
  Assert-MIR42FourTargetOutputAdmission -OutputRoot $output
  $resourceAdmission = Get-MIR42FourTargetCapacityAdmission -OutputRoot $output -MinimumFreeMemoryBytes $MinimumFreeMemoryBytes -MinimumFreeWorkBytes $MinimumFreeWorkBytes

  $preflight = [pscustomobject][ordered]@{
    source = [pscustomobject][ordered]@{ commit = $headCommit; tree = $headTree }
    package_authority_sha256 = [string]$packageAuthority.record_sha256
    package_source_sha256 = $packageSourceSha256
    target_authority = @(
      foreach ($target in $targets) {
        $identity = $identities[$target]
        [pscustomobject][ordered]@{
          target = $target
          target_id = [string]$identity.target_id
          source_version = [string]$identity.source_version
          distribution_version = [string]$identity.distribution_version
        }
      }
    )
    resource_admission = $resourceAdmission
  }
  $workRoot = Resolve-MIR4ArtifactPath -OutputRoot $output -RelativePath 'work'
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
  $rows = [Collections.Generic.List[object]]::new()
  $failures = [Collections.Generic.List[object]]::new()

  foreach ($target in $targets) {
    $identity = $identities[$target]
    try {
      Assert-MIR42FourTargetCleanSnapshot -RepoRoot $repo -ExpectedCommit $headCommit -ExpectedTree $headTree -ExpectedPackageSourceSha256 $packageSourceSha256
      $targetWork = Resolve-MIR4ArtifactPath -OutputRoot $workRoot -RelativePath $target
      New-Item -ItemType Directory -Force -Path $targetWork | Out-Null
      $candidatePrefix = "M42-$BuildId-$($target.ToUpperInvariant())"
      $a = New-MIR4TargetPackage -RepoRoot $repo -Target $target -CandidateId "$candidatePrefix-A" -SourceVersion '4.2.0' -DistributionVersion ([string]$identity.distribution_version) -OutputRoot $targetWork
      $aInventory = Get-MIR42FourTargetVerifiedMaterialization -Materialization $a -ExpectedRoot ([string]$identity.distribution_root) -ExpectedVersion ([string]$identity.distribution_version)
      $aCandidateRoot = Split-Path -Parent ([string]$a.tree_path)
      Remove-MIR4BuildTree -OutputRoot $targetWork -Path $aCandidateRoot

      Assert-MIR42FourTargetCleanSnapshot -RepoRoot $repo -ExpectedCommit $headCommit -ExpectedTree $headTree -ExpectedPackageSourceSha256 $packageSourceSha256
      $b = New-MIR4TargetPackage -RepoRoot $repo -Target $target -CandidateId "$candidatePrefix-B" -SourceVersion '4.2.0' -DistributionVersion ([string]$identity.distribution_version) -OutputRoot $targetWork
      $bInventory = Get-MIR42FourTargetVerifiedMaterialization -Materialization $b -ExpectedRoot ([string]$identity.distribution_root) -ExpectedVersion ([string]$identity.distribution_version)
      if ([string]$aInventory.archive_sha256 -cne [string]$bInventory.archive_sha256 -or
          [string]$aInventory.content_sha256 -cne [string]$bInventory.content_sha256 -or
          [int]$aInventory.entry_count -ne [int]$bInventory.entry_count) {
        throw "[mir42-four-target-nondeterministic] $target"
      }

      $assetRelative = "assets/$target/$([string]$identity.package_name)"
      $assetPath = Resolve-MIR4ArtifactPath -OutputRoot $output -RelativePath $assetRelative
      $assetParent = Split-Path -Parent $assetPath
      New-Item -ItemType Directory -Force -Path $assetParent | Out-Null
      Copy-Item -LiteralPath ([string]$b.archive_path) -Destination $assetPath -ErrorAction Stop
      $assetIdentity = Get-MIR4RawFileIdentity -Path $assetPath
      if ([string]$assetIdentity.sha256 -cne [string]$bInventory.archive_sha256) {
        throw "[mir42-four-target-custody-copy] $target"
      }
      $copiedInventory = Get-MIR4ArchiveInventory -Path $assetPath
      if ([string]$copiedInventory.content_sha256 -cne [string]$bInventory.content_sha256 -or
          [int]$copiedInventory.entry_count -ne [int]$bInventory.entry_count) {
        throw "[mir42-four-target-custody-content] $target"
      }

      $row = [pscustomobject][ordered]@{
        schema = 1
        kind = 'MIR42FourTargetCandidateRowV1'
        status = 'accepted-private-deterministic-unqualified'
        target = $target
        source = $preflight.source
        source_version = [string]$identity.source_version
        distribution_version = [string]$identity.distribution_version
        package_authority_sha256 = [string]$packageAuthority.record_sha256
        package_source_sha256 = $packageSourceSha256
        asset = [pscustomobject][ordered]@{
          path = $assetRelative
          bytes = [Int64]$assetIdentity.bytes
          sha256 = [string]$assetIdentity.sha256
        }
        content_sha256 = [string]$bInventory.content_sha256
        entry_count = [int]$bInventory.entry_count
        build_a_sha256 = [string]$aInventory.archive_sha256
        build_b_sha256 = [string]$bInventory.archive_sha256
        deterministic_archive_bytes = $true
        package_excluded_surface = $true
        materializer_record_a_sha256 = [string]$a.record_sha256
        materializer_record_b_sha256 = [string]$b.record_sha256
        expanded_success_roots = 'removed'
        qualification = 'not-performed'
        technical_seal = 'not-performed'
        signing = 'not-performed'
        publication_authorized = $false
        record_sha256 = ''
      }
      Write-MIR42FourTargetTargetRow -OutputRoot $output -Row $row | Out-Null
      $rows.Add($row)
      Remove-MIR4BuildTree -OutputRoot $targetWork -Path (Split-Path -Parent ([string]$b.tree_path))
      Assert-MIR42FourTargetCleanSnapshot -RepoRoot $repo -ExpectedCommit $headCommit -ExpectedTree $headTree -ExpectedPackageSourceSha256 $packageSourceSha256
    } catch {
      $failures.Add([pscustomobject][ordered]@{
        target = $target
        phase = 'deterministic-materialization'
        error = [string]$_.Exception.Message
      })
      break
    }
  }

  return Write-MIR42FourTargetManifest -OutputRoot $output -Preflight $preflight -Rows $rows.ToArray() -Failures $failures.ToArray()
}
