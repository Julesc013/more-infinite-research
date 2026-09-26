Set-StrictMode -Version Latest

$mir42CandidateBuildRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
$script:MIR42CanonicalCandidateTargets = @('f210', 'f200', 'f110', 'f100')
$script:MIR42HistoricalCandidateTargets = @('f017', 'f016', 'f015', 'f014', 'f013')
$script:MIR42NineTargetCandidateOrder = @($script:MIR42CanonicalCandidateTargets + $script:MIR42HistoricalCandidateTargets)
$script:MIR42CanonicalCandidateLines = [ordered]@{ f210 = '2.1'; f200 = '2.0'; f110 = '1.1'; f100 = '1.0' }
$script:MIR42HistoricalCandidateLines = [ordered]@{ f017 = '0.17'; f016 = '0.16'; f015 = '0.15'; f014 = '0.14'; f013 = '0.13' }
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

function Assert-MIR42HistoricalCandidateTargetRecord {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)]$Record
  )

  $expectedLine = [string]$script:MIR42HistoricalCandidateLines[$Target]
  $expectedVersion = "4.2.$($Target.Substring(1))00"
  if ([string]::IsNullOrWhiteSpace($expectedLine) -or [int]$Record.schema -ne 1 -or
      [string]$Record.kind -cne 'MIR42HistoricalPlaytestTargetV1' -or [string]$Record.target -cne $Target -or
      -not (Test-MIR4BootstrapRecordHash -Record $Record) -or [string]$Record.base_materializer_target -cne 'f100' -or
      [string]$Record.factorio_line -cne $expectedLine -or [string]$Record.distribution_version -cne $expectedVersion -or
      [bool]$Record.public_output_authorized -or [bool]$Record.publication_authorized -or
      [string]::IsNullOrWhiteSpace([string]$Record.engine.version) -or [string]::IsNullOrWhiteSpace([string]$Record.engine.sha256) -or
      [string]::IsNullOrWhiteSpace([string]$Record.predecessor.version) -or [string]::IsNullOrWhiteSpace([string]$Record.predecessor.archive) -or
      [string]::IsNullOrWhiteSpace([string]$Record.predecessor.sha256)) {
    throw "[mir42-candidate-historical-target-record-invalid] $Target"
  }
}

function Get-MIR42CandidateTargetDescriptors {
  <#
    The existing canonical materializer owns the modern four targets.  Historical
    targets are composed through their bounded target records and historical
    materializer.  This selector is deliberately narrow: a release candidate is
    either the established modern four or the ordered nine-target candidate.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string[]]$SelectedTargets = $script:MIR42CanonicalCandidateTargets
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $selected = @($SelectedTargets | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
  if ($selected.Count -eq 0 -or @($selected | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -ne 0) {
    throw '[mir42-candidate-target-selection-empty]'
  }
  if (@($selected | Sort-Object -Unique).Count -ne $selected.Count) {
    throw '[mir42-candidate-target-selection-duplicate]'
  }
  $canonicalSelection = ($selected -join '|') -ceq ($script:MIR42CanonicalCandidateTargets -join '|')
  $nineSelection = ($selected -join '|') -ceq ($script:MIR42NineTargetCandidateOrder -join '|')
  if (-not $canonicalSelection -and -not $nineSelection) {
    throw '[mir42-candidate-target-selection-unsupported]'
  }

  $packageAuthority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $authorityTargets = @($packageAuthority.targets | ForEach-Object { [string]$_.target })
  if ($authorityTargets.Count -ne $script:MIR42CanonicalCandidateTargets.Count -or
      ($authorityTargets -join '|') -cne ($script:MIR42CanonicalCandidateTargets -join '|')) {
    throw '[mir42-candidate-canonical-authority-target-set]'
  }
  $packageSourceSha256 = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
  $descriptors = [Collections.Generic.List[object]]::new()
  foreach ($target in $selected) {
    if ($target -in $script:MIR42CanonicalCandidateTargets) {
      $identity = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $repo -Target $target -SourceVersion '4.2.0'
      $descriptors.Add([pscustomobject][ordered]@{
        target = $target
        target_id = [string]$identity.target_id
        factorio_line = [string]$script:MIR42CanonicalCandidateLines[$target]
        source_version = [string]$identity.source_version
        distribution_version = [string]$identity.distribution_version
        materializer = 'canonical-package-source'
        canonical_identity = $identity
        package_authority_sha256 = [string]$packageAuthority.record_sha256
        package_source_sha256 = $packageSourceSha256
        public_output_authorized = $false
        publication_authorized = $false
      })
      continue
    }

    $recordRelative = "targets/historical/$target/target.json"
    $recordPath = Join-Path $repo $recordRelative
    if (-not (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
      throw "[mir42-candidate-historical-target-record-missing] $target"
    }
    $record = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR42HistoricalCandidateTargetRecord -Target $target -Record $record
    $descriptors.Add([pscustomobject][ordered]@{
      target = $target
      target_id = "factorio-$([string]$record.factorio_line)"
      factorio_line = [string]$record.factorio_line
      source_version = '4.2.0'
      distribution_version = [string]$record.distribution_version
      materializer = 'historical-playtest-target'
      base_materializer_target = [string]$record.base_materializer_target
      target_record = [pscustomobject][ordered]@{
        path = $recordRelative.Replace('\', '/')
        sha256 = [string]$record.record_sha256
      }
      engine = [pscustomobject][ordered]@{
        version = [string]$record.engine.version
        sha256 = [string]$record.engine.sha256
      }
      predecessor = [pscustomobject][ordered]@{
        version = [string]$record.predecessor.version
        archive = [string]$record.predecessor.archive
        sha256 = [string]$record.predecessor.sha256
      }
      package_authority_sha256 = [string]$packageAuthority.record_sha256
      package_source_sha256 = $packageSourceSha256
      public_output_authorized = $false
      publication_authorized = $false
    })
  }
  return @($descriptors.ToArray())
}

function Read-MIR42HistoricalCandidateConstructionRow {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Descriptor,
    [Parameter(Mandatory)][string]$ManifestPath
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if ([string]$Descriptor.materializer -cne 'historical-playtest-target') {
    throw '[mir42-candidate-historical-construction-descriptor]'
  }
  $path = (Resolve-Path -LiteralPath $ManifestPath).Path
  $manifest = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100 -DateKind String
  $head = (& git -C $repo rev-parse HEAD).Trim()
  $tree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  if ($LASTEXITCODE -ne 0 -or [int]$manifest.schema -ne 1 -or -not (Test-MIR4BootstrapRecordHash -Record $manifest) -or
      [string]$manifest.kind -cne 'MIR42HistoricalPlaytestCandidateManifestV1' -or
      [string]$manifest.status -cne 'built-private-historical-unqualified' -or
      [string]$manifest.target -cne [string]$Descriptor.target -or
      [string]$manifest.source.commit -cne $head -or [string]$manifest.source.tree -cne $tree -or
      [string]$manifest.source.canonical_base_target -cne [string]$Descriptor.base_materializer_target -or
      [string]$manifest.factorio_line -cne [string]$Descriptor.factorio_line -or
      [string]$manifest.distribution_version -cne [string]$Descriptor.distribution_version -or
      [string]$manifest.target_record.path -cne [string]$Descriptor.target_record.path -or
      [string]$manifest.target_record.sha256 -cne [string]$Descriptor.target_record.sha256 -or
      [string]$manifest.engine.version -cne [string]$Descriptor.engine.version -or
      [string]$manifest.engine.sha256 -cne [string]$Descriptor.engine.sha256 -or
      [string]$manifest.predecessor.version -cne [string]$Descriptor.predecessor.version -or
      [string]$manifest.predecessor.archive -cne [string]$Descriptor.predecessor.archive -or
      [string]$manifest.predecessor.sha256 -cne [string]$Descriptor.predecessor.sha256 -or
      [bool]$manifest.public_output_authorized -or [bool]$manifest.publication_authorized) {
    throw '[mir42-candidate-historical-construction-manifest]'
  }
  $row = $manifest.candidate_row
  if ($null -eq $row -or [int]$row.schema -ne 1 -or [string]$row.kind -cne 'MIR42HistoricalCandidateRowV1' -or
      [string]$row.status -cne 'deterministic-historical-candidate-construction-input-unqualified' -or
      [string]$row.target -cne [string]$Descriptor.target -or
      [string]$row.source.commit -cne $head -or [string]$row.source.tree -cne $tree -or
      [string]$row.source_version -cne [string]$Descriptor.source_version -or
      [string]$row.distribution_version -cne [string]$Descriptor.distribution_version -or
      [string]$row.base_materializer_target -cne [string]$Descriptor.base_materializer_target -or
      [string]$row.target_record.path -cne [string]$Descriptor.target_record.path -or
      [string]$row.target_record.sha256 -cne [string]$Descriptor.target_record.sha256 -or
      -not [bool]$row.deterministic_archive_bytes -or -not [bool]$row.package_excluded_surface -or
      [bool]$row.public_output_authorized -or [bool]$row.publication_authorized -or
      [string]::IsNullOrWhiteSpace([string]$row.asset.path) -or [IO.Path]::IsPathRooted([string]$row.asset.path) -or
      [string]$row.asset.path -match '(^|[\\/])[.][.]([\\/]|$)') {
    throw '[mir42-candidate-historical-construction-row]'
  }
  $outputRoot = Split-Path -Parent (Split-Path -Parent $path)
  $assetPath = [IO.Path]::GetFullPath((Join-Path $outputRoot ([string]$row.asset.path)))
  $outputPrefix = $outputRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  if (-not $assetPath.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
    throw '[mir42-candidate-historical-construction-asset-path]'
  }
  if ([string]::IsNullOrWhiteSpace([string]$manifest.distribution.path) -or [IO.Path]::IsPathRooted([string]$manifest.distribution.path) -or
      [string]$manifest.distribution.path -match '(^|[\\/])[.][.]([\\/]|$)') {
    throw '[mir42-candidate-historical-construction-distribution-path]'
  }
  $manifestAssetPath = [IO.Path]::GetFullPath((Join-Path $repo ([string]$manifest.distribution.path)))
  if (-not $manifestAssetPath.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase) -or
      -not [string]::Equals($manifestAssetPath, $assetPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw '[mir42-candidate-historical-construction-distribution-path]'
  }
  $inventory = Get-MIR4ArchiveInventory -Path $assetPath
  $expectedRoot = "more-infinite-research_$([string]$Descriptor.distribution_version)"
  Assert-MIR42FourTargetPackageSurface -Inventory $inventory -ExpectedRoot $expectedRoot -ExpectedVersion ([string]$Descriptor.distribution_version)
  if ([string]$inventory.archive_sha256 -cne [string]$row.asset.sha256 -or
      [int64]$inventory.bytes -ne [int64]$row.asset.bytes -or
      [string]$inventory.content_sha256 -cne [string]$row.content_sha256 -or
      [int]$inventory.entry_count -ne [int]$row.entry_count -or
      [string]$row.build_a_sha256 -cne [string]$row.asset.sha256 -or
      [string]$row.build_b_sha256 -cne [string]$row.asset.sha256 -or
      [string]$manifest.distribution.sha256 -cne [string]$row.asset.sha256 -or
      [string]$manifest.distribution.content_sha256 -cne [string]$row.content_sha256 -or
      [int]$manifest.distribution.entry_count -ne [int]$row.entry_count) {
    throw '[mir42-candidate-historical-construction-asset-identity]'
  }
  $row | Add-Member -NotePropertyName historical_materializer_manifest_sha256 -NotePropertyValue ([string]$manifest.record_sha256)
  return $row
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

  $targetCount = @($Preflight.target_authority).Count
  if ($targetCount -notin @(4, 9)) {
    throw '[mir42-candidate-manifest-target-count]'
  }
  $scope = if ($targetCount -eq 4) { 'four-target' } else { 'nine-target' }
  $complete = $Failures.Count -eq 0 -and $Rows.Count -eq $targetCount
  $manifest = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42FourTargetDeterministicCandidateManifestV1'
    status = if ($complete) {
      "private-deterministic-$scope-candidate-built-unqualified"
    } else {
      "private-deterministic-$scope-candidate-partial"
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
    [string[]]$SelectedTargets = $script:MIR42CanonicalCandidateTargets,
    [string]$OutputRoot,
    [ValidateRange(1, 9223372036854775807)][Int64]$MinimumFreeMemoryBytes = 1GB,
    [ValidateRange(1, 9223372036854775807)][Int64]$MinimumFreeWorkBytes = 2GB
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $descriptors = @(Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SelectedTargets $SelectedTargets)
  $targets = @($descriptors | ForEach-Object { [string]$_.target })
  $candidateScope = if ($targets.Count -eq 4) { 'four-target' } elseif ($targets.Count -eq 9) { 'nine-target' } else { throw '[mir42-candidate-construction-target-count]' }
  if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path "build/mir42-$candidateScope-candidates" $BuildId
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
  $identities = [ordered]@{}
  $expectedVersions = [ordered]@{ f210 = '4.2.21000'; f200 = '4.2.20000'; f110 = '4.2.11000'; f100 = '4.2.10000' }
  foreach ($descriptor in $descriptors) {
    $target = [string]$descriptor.target
    if ([string]$descriptor.materializer -ceq 'canonical-package-source') {
      $identity = $descriptor.canonical_identity
      if ($null -eq $identity -or [string]$identity.distribution_version -cne [string]$expectedVersions[$target]) {
        throw "[mir42-four-target-construction-descriptor] $target"
      }
      $identities[$target] = $identity
      continue
    }
    if ([string]$descriptor.materializer -cne 'historical-playtest-target' -or
        [string]::IsNullOrWhiteSpace([string]$descriptor.target_record.sha256) -or
        [string]::IsNullOrWhiteSpace([string]$descriptor.engine.sha256) -or
        [string]::IsNullOrWhiteSpace([string]$descriptor.predecessor.sha256)) {
      throw "[mir42-nine-target-historical-construction-descriptor] $target"
    }
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
      foreach ($descriptor in $descriptors) {
        [pscustomobject][ordered]@{
          target = [string]$descriptor.target
          target_id = [string]$descriptor.target_id
          source_version = [string]$descriptor.source_version
          distribution_version = [string]$descriptor.distribution_version
        }
      }
    )
    resource_admission = $resourceAdmission
  }
  $workRoot = Resolve-MIR4ArtifactPath -OutputRoot $output -RelativePath 'work'
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
  $rows = [Collections.Generic.List[object]]::new()
  $failures = [Collections.Generic.List[object]]::new()
  $historicalScript = Join-Path $repo 'tools/commands/release/New-MIR42HistoricalPlaytestCandidate.ps1'

  foreach ($descriptor in $descriptors) {
    $target = [string]$descriptor.target
    try {
      Assert-MIR42FourTargetCleanSnapshot -RepoRoot $repo -ExpectedCommit $headCommit -ExpectedTree $headTree -ExpectedPackageSourceSha256 $packageSourceSha256
      $targetWork = Resolve-MIR4ArtifactPath -OutputRoot $workRoot -RelativePath $target
      New-Item -ItemType Directory -Force -Path $targetWork | Out-Null
      if ([string]$descriptor.materializer -ceq 'canonical-package-source') {
        $identity = $identities[$target]
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
        if (Test-Path -LiteralPath $assetPath -PathType Leaf) { throw "[mir42-candidate-asset-collision] $target" }
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

        # Preserve the established canonical row shape exactly for the four target default.
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
        Remove-MIR4BuildTree -OutputRoot $targetWork -Path (Split-Path -Parent ([string]$b.tree_path))
      } elseif ([string]$descriptor.materializer -ceq 'historical-playtest-target') {
        $construction = @(& $historicalScript -RepoRoot $repo -Target $target -CandidateId "M42-$BuildId-$($target.ToUpperInvariant())" -Repetitions 2 -OutputRoot $targetWork -Check)
        if ($LASTEXITCODE -ne 0 -or $construction.Count -ne 1) {
          throw "[mir42-nine-target-historical-materializer-result] $target"
        }
        $constructionManifestPath = Join-Path $targetWork "manifests/$target.json"
        $constructionRow = Read-MIR42HistoricalCandidateConstructionRow -RepoRoot $repo -Descriptor $descriptor -ManifestPath $constructionManifestPath
        $constructionAssetPath = [IO.Path]::GetFullPath((Join-Path $targetWork ([string]$constructionRow.asset.path)))
        $assetName = [IO.Path]::GetFileName($constructionAssetPath)
        if ([string]::IsNullOrWhiteSpace($assetName) -or $assetName -notmatch '\.zip$') {
          throw "[mir42-nine-target-historical-asset-name] $target"
        }
        $assetRelative = "assets/$target/$assetName"
        $assetPath = Resolve-MIR4ArtifactPath -OutputRoot $output -RelativePath $assetRelative
        if (Test-Path -LiteralPath $assetPath -PathType Leaf) { throw "[mir42-candidate-asset-collision] $target" }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $assetPath) | Out-Null
        Copy-Item -LiteralPath $constructionAssetPath -Destination $assetPath -ErrorAction Stop
        $assetIdentity = Get-MIR4RawFileIdentity -Path $assetPath
        $copiedInventory = Get-MIR4ArchiveInventory -Path $assetPath
        if ([string]$assetIdentity.sha256 -cne [string]$constructionRow.asset.sha256 -or
            [Int64]$assetIdentity.bytes -ne [Int64]$constructionRow.asset.bytes -or
            [string]$copiedInventory.content_sha256 -cne [string]$constructionRow.content_sha256 -or
            [int]$copiedInventory.entry_count -ne [int]$constructionRow.entry_count) {
          throw "[mir42-nine-target-historical-custody] $target"
        }

        $row = [pscustomobject][ordered]@{
          schema = 1
          kind = 'MIR42FourTargetCandidateRowV1'
          status = 'accepted-private-deterministic-unqualified'
          target = $target
          source = $preflight.source
          source_version = [string]$descriptor.source_version
          distribution_version = [string]$descriptor.distribution_version
          package_authority_sha256 = [string]$packageAuthority.record_sha256
          package_source_sha256 = $packageSourceSha256
          asset = [pscustomobject][ordered]@{
            path = $assetRelative
            bytes = [Int64]$assetIdentity.bytes
            sha256 = [string]$assetIdentity.sha256
          }
          content_sha256 = [string]$copiedInventory.content_sha256
          entry_count = [int]$copiedInventory.entry_count
          build_a_sha256 = [string]$constructionRow.build_a_sha256
          build_b_sha256 = [string]$constructionRow.build_b_sha256
          deterministic_archive_bytes = $true
          package_excluded_surface = $true
          materializer = 'historical-playtest-target'
          base_materializer_target = [string]$descriptor.base_materializer_target
          target_record = $descriptor.target_record
          factorio_line = [string]$descriptor.factorio_line
          engine = $descriptor.engine
          predecessor = $descriptor.predecessor
          historical_materializer_manifest_sha256 = [string]$constructionRow.historical_materializer_manifest_sha256
          qualification = 'not-performed'
          technical_seal = 'not-performed'
          signing = 'not-performed'
          public_output_authorized = $false
          publication_authorized = $false
          record_sha256 = ''
        }
        Remove-MIR4BuildTree -OutputRoot $workRoot -Path $targetWork
      } else {
        throw "[mir42-candidate-materializer-unknown] $target"
      }

      Write-MIR42FourTargetTargetRow -OutputRoot $output -Row $row | Out-Null
      $rows.Add($row)
      Assert-MIR42FourTargetCleanSnapshot -RepoRoot $repo -ExpectedCommit $headCommit -ExpectedTree $headTree -ExpectedPackageSourceSha256 $packageSourceSha256
    } catch {
      $failures.Add([pscustomobject][ordered]@{
        target = $target
        phase = if ([string]$descriptor.materializer -ceq 'historical-playtest-target') { 'historical-deterministic-materialization' } else { 'deterministic-materialization' }
        error = [string]$_.Exception.Message
      })
      break
    }
  }

  return Write-MIR42FourTargetManifest -OutputRoot $output -Preflight $preflight -Rows $rows.ToArray() -Failures $failures.ToArray()
}
