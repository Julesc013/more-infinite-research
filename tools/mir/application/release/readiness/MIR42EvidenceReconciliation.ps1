Set-StrictMode -Version Latest

$mir42QualificationRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42QualificationRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Get-MIR4CanonicalPackageAuthority -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42QualificationRoot 'tools/mir/application/package/PackageAuthority.ps1')
}
if (-not (Get-Command Get-MIR4FixedFactorioEngineLock -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42QualificationRoot 'tools/lib/validation/FactorioVersionPolicy.ps1')
}
if (-not (Get-Command Get-MIR42ReleaseTargetIdentity -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42QualificationRoot 'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1')
}

$script:MIR42QualificationTargets = @('f210', 'f200', 'f110', 'f100')
$script:MIR42QualificationHistoricalTargets = @('f017', 'f016', 'f015', 'f014', 'f013')
$script:MIR42QualificationNineTargets = @($script:MIR42QualificationTargets + $script:MIR42QualificationHistoricalTargets)
$script:MIR42QualificationLines = [ordered]@{ f210 = '2.1'; f200 = '2.0'; f110 = '1.1'; f100 = '1.0'; f017 = '0.17'; f016 = '0.16'; f015 = '0.15'; f014 = '0.14'; f013 = '0.13' }
$script:MIR42QualificationAssertions = @(
  'exact-candidate-normal-mod-directory-load',
  'upgraded-save-reload-passed',
  'upgraded-save-second-reload-passed'
)
$script:MIR42QualificationHistoricalAssertions = @(
  'historical-terminal-source-state-retained',
  'historical-terminal-researched-level-retained',
  'historical-terminal-current-research-retained',
  'historical-terminal-fractional-progress-retained',
  'historical-terminal-infinite-bonus-retained-where-supported',
  'historical-terminal-global-state-retained'
)

function Get-MIR42QualificationTargetScope {
  param([Parameter(Mandatory)]$Rows,[Parameter(Mandatory)][string]$Code)
  $actual = @($Rows | ForEach-Object { [string]$_.target })
  if (($actual -join '|') -ceq ($script:MIR42QualificationTargets -join '|')) { return 'four-target' }
  if (($actual -join '|') -ceq ($script:MIR42QualificationNineTargets -join '|')) { return 'nine-target' }
  throw "[$Code-target-set]"
}

function Get-MIR42QualificationScopeContract {
  param([Parameter(Mandatory)][ValidateSet('four-target','nine-target')][string]$Scope)
  if ($Scope -ceq 'four-target') {
    return [pscustomobject][ordered]@{
      targets = @($script:MIR42QualificationTargets)
      candidate_status = 'private-deterministic-four-target-candidate-built-unqualified'
      kind = 'MIR42FourTargetEvidenceReconciliationV1'
      status = 'MIR-4.2-FOUR-TARGET-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED'
      target_requirement = 'all_four_targets_required'
    }
  }
  return [pscustomobject][ordered]@{
    targets = @($script:MIR42QualificationNineTargets)
    candidate_status = 'private-deterministic-nine-target-candidate-built-unqualified'
    kind = 'MIR42NineTargetEvidenceReconciliationV1'
    status = 'MIR-4.2-NINE-TARGET-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED'
    target_requirement = 'all_nine_targets_required'
  }
}

function Assert-MIR42QualificationOutputRoot {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$OutputRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $build = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
  $root = if ([IO.Path]::IsPathRooted($OutputRoot)) {
    [IO.Path]::GetFullPath($OutputRoot)
  } else {
    [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
  }
  $null = Assert-MIR4DescendantPath -Root $build -Path $root
  $null = Assert-MIR4NoReparseAncestors -Root $repo -Path $root
  if (Test-Path -LiteralPath $root -PathType Leaf) { throw '[mir42-qualification-output-file]' }
  if (Test-Path -LiteralPath $root -PathType Container) {
    if (@(Get-ChildItem -LiteralPath $root -Force).Count -ne 0) { throw '[mir42-qualification-output-not-empty]' }
  } else {
    New-Item -ItemType Directory -Force -Path $root | Out-Null
  }
  return $root
}

function Get-MIR42QualificationCurrentSource {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $dirty = @(& git -C $RepoRoot status --porcelain --untracked-files=no 2>$null)
  if ($LASTEXITCODE -ne 0) { throw '[mir42-qualification-source-status]' }
  if ($dirty.Count -ne 0) { throw '[mir42-qualification-source-dirty]' }
  $commit = @(& git -C $RepoRoot rev-parse HEAD 2>$null)
  $tree = @(& git -C $RepoRoot rev-parse 'HEAD^{tree}' 2>$null)
  if ($LASTEXITCODE -ne 0 -or $commit.Count -ne 1 -or $tree.Count -ne 1 -or
      ([string]$commit[0]).Trim() -notmatch '^[a-f0-9]{40}$' -or ([string]$tree[0]).Trim() -notmatch '^[a-f0-9]{40}$') {
    throw '[mir42-qualification-source-identity]'
  }
  return [pscustomobject][ordered]@{ commit = ([string]$commit[0]).Trim(); tree = ([string]$tree[0]).Trim() }
}

function Read-MIR42QualificationBootstrapRecord {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "[$Code-missing]" }
  try {
    $record = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100 -DateKind String
  } catch {
    throw "[$Code-json]"
  }
  if (-not (Test-MIR4BootstrapRecordHash -Record $record)) { throw "[$Code-hash]" }
  return $record
}

function Resolve-MIR42QualificationChildPath {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Code
  )

  try { return Resolve-MIR4ArtifactPath -OutputRoot $Root -RelativePath $RelativePath }
  catch { throw "[$Code-path]" }
}

function Get-MIR42QualificationHistoricalAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][ValidateSet('f017','f016','f015','f014','f013')][string]$Target,
    [ValidateSet('4.2.0','4.2.1','4.2.2','4.2.3','4.3.0','4.3.1','4.4.0','4.4.1','4.4.2','4.5.0','4.5.2')][string]$SourceVersion = '4.2.0',
    [switch]$PredecessorIdentityOnly)
  $identity = Get-MIR42ReleaseTargetIdentity -RepoRoot $RepoRoot -Target $Target -SourceVersion $SourceVersion
  $baselineIdentity = New-MIR4DistributionIdentityProjection -DistributionTargetCode $Target.Substring(1) -SourceMinor 2 -SourcePatch 0
  if ($identity.PSObject.Properties.Name -notcontains 'target_record_path' -or
      [IO.Path]::IsPathRooted([string]$identity.target_record_path) -or [string]$identity.target_record_path -match '(^|[\\/])[.][.]([\\/]|$)') {
    throw "[mir42-qualification-historical-target-record-path] $Target"
  }
  $recordPath = Join-Path $RepoRoot ([string]$identity.target_record_path)
  $record = Read-MIR42QualificationBootstrapRecord -Path $recordPath -Code "mir42-qualification-historical-target-record-$Target"
  if ((Get-MIR4Sha256File -Path $recordPath) -cne [string]$identity.target_record_file_sha256 -or
      [string]$record.record_sha256 -cne [string]$identity.target_record_record_sha256 -or
      [int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42HistoricalPlaytestTargetV1' -or
      [string]$record.target -cne $Target -or [string]$record.maturity -cne 'private-historical-playtest' -or
      [string]$record.base_materializer_target -cne 'f100' -or [string]$record.factorio_line -cne [string]$script:MIR42QualificationLines[$Target] -or
      [string]$record.distribution_version -cne [string]$baselineIdentity.distribution_version -or
      [bool]$record.public_output_authorized -or [bool]$record.publication_authorized) {
    throw "[mir42-qualification-historical-target-record-state] $Target"
  }
  $sealRelative = '.mir/releases/terminal/seals/' + [string]$record.predecessor.version + '.json'
  $sealPath = Join-Path $RepoRoot $sealRelative
  $seal = Read-MIR42QualificationBootstrapRecord -Path $sealPath -Code "mir42-qualification-historical-terminal-seal-$Target"
  if ([int]$seal.schema -ne 1 -or [string]$seal.kind -cne 'Mir3TerminalTargetSealV1' -or [string]$seal.status -cne 'sealed' -or
      [string]$seal.release -cne [string]$record.predecessor.version -or [string]$seal.target -cne [string]$record.factorio_line -or
      [string]$seal.archive_sha256 -cne [string]$record.predecessor.sha256 -or [string]$seal.engine.version -cne [string]$record.engine.version -or
      [string]$seal.engine.binary_sha256 -cne [string]$record.engine.sha256) {
    throw "[mir42-qualification-historical-terminal-seal-binding] $Target"
  }
  if ([IO.Path]::IsPathRooted([string]$record.predecessor.archive) -or [string]$record.predecessor.archive -match '(^|[\\/])[.][.]([\\/]|$)') {
    throw "[mir42-qualification-historical-predecessor-path] $Target"
  }
  $predecessorPath = Join-Path $RepoRoot ([string]$record.predecessor.archive)
  $inventory = $null
  if (-not $PredecessorIdentityOnly) {
    $inventory = Get-MIR4ArchiveInventory -Path $predecessorPath
    if ([string]$inventory.archive_sha256 -cne [string]$seal.archive_sha256 -or [int64]$inventory.bytes -ne [int64]$seal.bytes -or
      [string]$inventory.content_sha256 -cne [string]$seal.content_sha256 -or [int]$inventory.entry_count -ne [int]$seal.entries) {
      throw "[mir42-qualification-historical-predecessor-binding] $Target"
    }
  }
  return [pscustomobject][ordered]@{identity=$identity;record=$record;record_path=$recordPath;seal=$seal;seal_path=$sealPath;predecessor_path=$predecessorPath;inventory=$inventory}
}

function Get-MIR42QualificationCandidateRows {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath
  )

  $manifestPath = (Resolve-Path -LiteralPath $CandidateManifestPath).Path
  $root = Split-Path -Parent $manifestPath
  $manifest = Read-MIR42QualificationBootstrapRecord -Path $manifestPath -Code 'mir42-qualification-candidate-manifest'
  $versionContract = Get-MIR42CandidateConstructionVersionContract -RepoRoot $RepoRoot -Manifest $manifest
  $schema = [string]$versionContract.schema_path
  if (-not (Get-Content -Raw -LiteralPath $manifestPath | Test-Json -SchemaFile $schema)) {
    throw '[mir42-qualification-candidate-manifest-schema]'
  }
  $targets = @($manifest.targets)
  $scope = Get-MIR42QualificationTargetScope -Rows $targets -Code 'mir42-qualification-candidate'
  $contract = Get-MIR42QualificationScopeContract -Scope $scope
  if ([string]$manifest.kind -cne [string]$versionContract.manifest_kind -or
      [string]$manifest.status -cne [string]$contract.candidate_status -or
      -not [bool]$manifest.build_complete) {
    throw '[mir42-qualification-candidate-manifest-status]'
  }
  $manifestCommit = [string]$manifest.source.commit
  $manifestTree = [string]$manifest.source.tree
  if ($manifestCommit -notmatch '^[a-f0-9]{40}$' -or $manifestTree -notmatch '^[a-f0-9]{40}$') {
    throw '[mir42-qualification-candidate-source-identity]'
  }
  $resolvedTree = @(& git -C $RepoRoot rev-parse "$manifestCommit^{tree}" 2>$null)
  if ($LASTEXITCODE -ne 0 -or $resolvedTree.Count -ne 1 -or ([string]$resolvedTree[0]).Trim() -cne $manifestTree) {
    throw '[mir42-qualification-candidate-source-drift]'
  }
  if ([string]$manifest.package_source_sha256 -cne (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot)) {
    throw '[mir42-qualification-candidate-source-drift]'
  }
  $targetAuthorities = @($manifest.target_authority)
  if ((Get-MIR42QualificationTargetScope -Rows $targetAuthorities -Code 'mir42-qualification-candidate-authority') -cne $scope) {
    throw '[mir42-qualification-candidate-target-set]'
  }

  $rows = [Collections.Generic.List[object]]::new()
  foreach ($target in @($contract.targets)) {
    $summary = @($targets | Where-Object { [string]$_.target -ceq $target })
    if ($summary.Count -ne 1) { throw "[mir42-qualification-candidate-target] $target" }
    $rowPath = Resolve-MIR42QualificationChildPath -Root $root -RelativePath ([string]$summary[0].target_row_path) -Code "mir42-qualification-target-row-$target"
    $row = Read-MIR42QualificationBootstrapRecord -Path $rowPath -Code "mir42-qualification-target-row-$target"
    if ([int]$row.schema -ne 1 -or [string]$row.kind -cne 'MIR42FourTargetCandidateRowV1' -or
        [string]$row.status -cne 'accepted-private-deterministic-unqualified' -or
        [string]$row.target -cne $target -or
        [string]$row.source.commit -cne [string]$manifest.source.commit -or
        [string]$row.source.tree -cne [string]$manifest.source.tree -or
        [string]$row.source_version -cne [string]$versionContract.source_version -or
        [string]$row.package_source_sha256 -cne [string]$manifest.package_source_sha256 -or
        -not [bool]$row.deterministic_archive_bytes -or
        -not [bool]$row.package_excluded_surface) {
      throw "[mir42-qualification-target-row-binding] $target"
    }

    $identity = Get-MIR42ReleaseTargetIdentity -RepoRoot $RepoRoot -Target $target -SourceVersion ([string]$versionContract.source_version)
    $targetAuthority = @($targetAuthorities | Where-Object { [string]$_.target -ceq $target })
    if ([string]$row.distribution_version -cne [string]$identity.distribution_version -or
        [string]$summary[0].distribution_version -cne [string]$identity.distribution_version -or
        $targetAuthority.Count -ne 1 -or [string]$targetAuthority[0].target_id -cne [string]$identity.target_id -or
        [string]$targetAuthority[0].distribution_version -cne [string]$identity.distribution_version) {
      throw "[mir42-qualification-target-version] $target"
    }
    $assetPath = Resolve-MIR42QualificationChildPath -Root $root -RelativePath ([string]$row.asset.path) -Code "mir42-qualification-candidate-asset-$target"
    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) { throw "[mir42-qualification-candidate-asset-missing] $target" }
    $inventory = Get-MIR4ArchiveInventory -Path $assetPath
    if ([string]$inventory.archive_sha256 -cne [string]$row.asset.sha256 -or
        [string]$inventory.archive_sha256 -cne [string]$summary[0].asset.sha256 -or
        [int64]$inventory.bytes -ne [int64]$row.asset.bytes -or
        [string]$inventory.content_sha256 -cne [string]$row.content_sha256 -or
        [string]$inventory.content_sha256 -cne [string]$summary[0].content_sha256 -or
        [int]$inventory.entry_count -ne [int]$row.entry_count -or
        [int]$inventory.entry_count -ne [int]$summary[0].entry_count -or
        [string]$inventory.root -cne [string]$identity.distribution_root) {
      throw "[mir42-qualification-candidate-identity] $target"
    }
    try {
      $info = Read-MIR4ArchiveText -Path $assetPath -RelativePath 'info.json' | ConvertFrom-Json -Depth 20 -DateKind String
    } catch {
      throw "[mir42-qualification-candidate-info] $target"
    }
    if ([string]$info.name -cne 'more-infinite-research' -or
        [string]$info.version -cne [string]$identity.distribution_version -or
        [string]$info.factorio_version -cne [string]$script:MIR42QualificationLines[$target]) {
      throw "[mir42-qualification-candidate-metadata] $target"
    }
    $historical = $null
    if ($target -in $script:MIR42QualificationHistoricalTargets) {
      $historical = Get-MIR42QualificationHistoricalAuthority -RepoRoot $RepoRoot -Target $target -SourceVersion ([string]$versionContract.source_version) -PredecessorIdentityOnly:([string]$versionContract.source_version -cne '4.2.0')
      foreach ($field in @('materializer','base_materializer_target','target_record','factorio_line','engine','predecessor','public_output_authorized','publication_authorized')) {
        if ($row.PSObject.Properties.Name -notcontains $field) { throw "[mir42-qualification-historical-target-row-field] $target/$field" }
      }
      if ([string]$row.materializer -cne 'historical-playtest-target' -or [string]$row.base_materializer_target -cne 'f100' -or
          [string]$row.target_record.path -cne [string]$historical.identity.target_record_path -or [string]$row.target_record.sha256 -cne [string]$historical.record.record_sha256 -or
          [string]$row.factorio_line -cne [string]$historical.record.factorio_line -or [string]$row.engine.version -cne [string]$historical.record.engine.version -or
          [string]$row.engine.sha256 -cne [string]$historical.record.engine.sha256 -or [string]$row.predecessor.version -cne [string]$historical.record.predecessor.version -or
          [string]$row.predecessor.archive -cne [string]$historical.record.predecessor.archive -or [string]$row.predecessor.sha256 -cne [string]$historical.record.predecessor.sha256 -or
          [bool]$row.public_output_authorized -or [bool]$row.publication_authorized) {
        throw "[mir42-qualification-historical-target-row-binding] $target"
      }
    }
    $rows.Add([pscustomobject][ordered]@{
      target = $target
      scope = $scope
      identity = $identity
      source = $row.source
      package_source_sha256 = [string]$manifest.package_source_sha256
      candidate_manifest = [pscustomobject][ordered]@{
        path = [IO.Path]::GetFileName($manifestPath)
        sha256 = Get-MIR4Sha256File -Path $manifestPath
        record_sha256 = [string]$manifest.record_sha256
      }
      target_row = [pscustomobject][ordered]@{
        path = [IO.Path]::GetRelativePath($root, $rowPath).Replace('\','/')
        sha256 = Get-MIR4Sha256File -Path $rowPath
        record_sha256 = [string]$row.record_sha256
      }
      archive = [pscustomobject][ordered]@{
        path = [IO.Path]::GetRelativePath($root, $assetPath).Replace('\','/')
        sha256 = [string]$inventory.archive_sha256
        bytes = [Int64]$inventory.bytes
        content_sha256 = [string]$inventory.content_sha256
        entry_count = [int]$inventory.entry_count
      }
      historical = $historical
    })
  }
  return @($rows)
}

function Get-MIR42QualificationPredecessor {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)]$Receipt,
    $PublishedMaintenanceInput = $null
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "[mir42-qualification-predecessor-missing] $Target" }
  $archive = (Resolve-Path -LiteralPath $Path).Path
  $inventory = Get-MIR4ArchiveInventory -Path $archive
  if ([string]$inventory.archive_sha256 -cne [string]$Receipt.from.sha256) {
    throw "[mir42-qualification-predecessor-hash] $Target"
  }
  try { $info = Read-MIR4ArchiveText -Path $archive -RelativePath 'info.json' | ConvertFrom-Json -Depth 20 -DateKind String }
  catch { throw "[mir42-qualification-predecessor-info] $Target" }
  if ([string]$info.name -cne 'more-infinite-research' -or
      [string]$info.version -cne [string]$Receipt.from.version -or
      [string]$info.factorio_version -cne [string]$script:MIR42QualificationLines[$Target]) {
    throw "[mir42-qualification-predecessor-metadata] $Target"
  }
  if ($null -ne $PublishedMaintenanceInput -and (
      [string]$PublishedMaintenanceInput.target -cne $Target -or
      -not $archive.Equals([string]$PublishedMaintenanceInput.path,[StringComparison]::OrdinalIgnoreCase) -or
      [string]$Receipt.from.version -cne [string]$PublishedMaintenanceInput.version -or
      [string]$inventory.archive_sha256 -cne [string]$PublishedMaintenanceInput.sha256 -or
      [int64]$inventory.bytes -ne [int64]$PublishedMaintenanceInput.bytes -or
      [string]$inventory.content_sha256 -cne [string]$PublishedMaintenanceInput.content_sha256 -or
      [int]$inventory.entry_count -ne [int]$PublishedMaintenanceInput.entry_count)) {
    throw "[mir42-qualification-published-maintenance-predecessor-binding] $Target"
  }
  return [pscustomobject][ordered]@{
    version = [string]$Receipt.from.version
    archive = [pscustomobject][ordered]@{
      path = [IO.Path]::GetFileName($archive)
      sha256 = [string]$inventory.archive_sha256
      bytes = [Int64]$inventory.bytes
      content_sha256 = [string]$inventory.content_sha256
      entry_count = [int]$inventory.entry_count
    }
  }
}

function Test-MIR42QualificationHistoricalFileVersion {
  param([Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$AuthorityVersion,[AllowEmptyString()][string]$ObservedVersion)
  if ($AuthorityVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { return $false }
  # The pinned 0.13 executable has no Windows FileVersion resource. Its exact
  # binary hash remains mandatory; later engines expose a four-part version.
  if ($Target -ceq 'f013') { return $ObservedVersion -ceq '' }
  return $ObservedVersion -cmatch ('^' + [regex]::Escape($AuthorityVersion) + '\.[0-9]+$')
}

function Get-MIR42QualificationEnvironment {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)]$Receipt)

  $receiptVersion = [string]$Receipt.factorio_binary_version
  $receiptSha = [string]$Receipt.factorio_binary_sha256
  if ($receiptSha -notmatch '^[A-F0-9]{64}$') {
    throw "[mir42-qualification-environment-identity] $Target"
  }
  if ($Target -in $script:MIR42QualificationHistoricalTargets) {
    # Engine identity is independent of the bytes of an obsolete mod archive.
    # The selected predecessor is authenticated separately by the caller.
    $historical = Get-MIR42QualificationHistoricalAuthority -RepoRoot $RepoRoot -Target $Target -PredecessorIdentityOnly
    if (-not (Test-MIR42QualificationHistoricalFileVersion -Target $Target -AuthorityVersion ([string]$historical.record.engine.version) -ObservedVersion $receiptVersion) -or
        [string]$receiptSha -cne [string]$historical.record.engine.sha256) {
      throw "[mir42-qualification-environment-historical] $Target"
    }
    return [pscustomobject][ordered]@{
      factorio_line = [string]$historical.record.factorio_line
      version = [string]$historical.record.engine.version
      observed_file_version = $receiptVersion
      version_authority = 'historical-target-record'
      binary_sha256 = $receiptSha
      policy = [pscustomobject][ordered]@{
        target_record = [pscustomobject][ordered]@{path=[string]$historical.identity.target_record_path;sha256=[string]$historical.record.record_sha256}
        terminal_seal = [pscustomobject][ordered]@{path=('.mir/releases/terminal/seals/' + [string]$historical.record.predecessor.version + '.json');sha256=[string]$historical.seal.record_sha256}
      }
    }
  }
  if ($receiptVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$') {
    throw "[mir42-qualification-environment-identity] $Target"
  }
  if ($Target -ceq 'f210') {
    $channelPath = Join-Path $RepoRoot 'spec/engines/mir4-factorio-2.1-experimental-channel-v1.json'
    $channel = Get-Content -Raw -LiteralPath $channelPath | ConvertFrom-Json -Depth 100 -DateKind String
    if ([string]$receiptVersion -cne [string]$channel.current_review.file_version -or
        [string]$receiptSha -cne [string]$channel.current_review.binary_sha256) {
      throw '[mir42-qualification-environment-f210]'
    }
    return [pscustomobject][ordered]@{
      factorio_line = '2.1'
      version = $receiptVersion
      binary_sha256 = $receiptSha
      policy = [pscustomobject][ordered]@{
        path = 'spec/engines/mir4-factorio-2.1-experimental-channel-v1.json'
        sha256 = Get-MIR4Sha256File -Path $channelPath
        review_status = [string]$channel.current_review.status
      }
    }
  }

  $lock = Get-MIR4FixedFactorioEngineLock -Target $Target -RepoRoot $RepoRoot
  if ([string]$receiptVersion -cne [string]$lock.file_version -or
      [string]$receiptSha -cne [string]$lock.binary_sha256) {
    throw "[mir42-qualification-environment-fixed] $Target"
  }
  return [pscustomobject][ordered]@{
    factorio_line = [string]$script:MIR42QualificationLines[$Target]
    version = $receiptVersion
    binary_sha256 = $receiptSha
    policy = [pscustomobject][ordered]@{
      selection = [string]$lock.selection
      authority_paths = @($lock.authority_paths)
    }
  }
}

function Assert-MIR42QualificationDirectLibraryUpgradeReceipt {
  param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)][string]$Target)
  $code = "[mir42-qualification-upgrade-direct-library] $Target"
  $hasHash = $Receipt.PSObject.Properties.Name -contains 'harness_sha256'
  $hasDirty = $Receipt.PSObject.Properties.Name -contains 'harness_worktree_dirty'
  $materialized = $Receipt.PSObject.Properties.Name -contains 'candidate_materialization'
  if ($hasHash -ne $hasDirty -or ($materialized -and -not $hasHash) -or
      $Receipt.PSObject.Properties.Name -notcontains 'factorio_processes' -or
      $Receipt.factorio_processes -ne 4) { throw $code }
  if ($hasHash -and ([string]$Receipt.harness_sha256 -cnotmatch '^[A-F0-9]{64}$' -or
      $Receipt.harness_worktree_dirty -isnot [bool] -or $Receipt.harness_worktree_dirty)) { throw $code }
  foreach ($phase in @('source_library_activation','library_activation')) {
    if ($Receipt.PSObject.Properties.Name -notcontains $phase) { throw $code }
    $activation = $Receipt.$phase
    foreach ($field in @('status','dependency_payload_bytes_copied','archive_links_created','archive_extractions','selected')) {
      if ($null -eq $activation -or $activation.PSObject.Properties.Name -notcontains $field) { throw $code }
    }
    if ([string]$activation.status -cne 'restored-direct-library-controls' -or
        $activation.dependency_payload_bytes_copied -ne 0 -or
        $activation.archive_links_created -ne 0 -or $activation.archive_extractions -ne 0 -or
        $activation.selected -isnot [array]) { throw $code }
    $mir = @($activation.selected | Where-Object { [string]$_.name -ceq 'more-infinite-research' })
    $expected = if ($phase -ceq 'source_library_activation') { $Receipt.from } else { $Receipt.to }
    if ($mir.Count -ne 1 -or [string]$mir[0].version -cne [string]$expected.version -or
        [string]$mir[0].sha256 -cne [string]$expected.sha256) { throw $code }
  }
}

function Get-MIR42QualificationUpgradeReceipt {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Candidate
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "[mir42-qualification-upgrade-receipt-missing] $Target" }
  $receiptPath = (Resolve-Path -LiteralPath $Path).Path
  try { $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100 -DateKind String }
  catch { throw "[mir42-qualification-upgrade-receipt-json] $Target" }
  if ([int]$receipt.schema -notin @(2,3) -or [string]$receipt.status -cne 'passed' -or
      [string]$receipt.archetype -cne 'base-default' -or
      [string]$receipt.git_commit -notmatch '^[a-f0-9]{40}$' -or
      [string]$receipt.to.version -cne [string]$Candidate.identity.distribution_version -or
      [string]$receipt.to.sha256 -cne [string]$Candidate.archive.sha256) {
    throw "[mir42-qualification-upgrade-receipt-binding] $Target"
  }
  if ([int]$receipt.schema -eq 3) {
    Assert-MIR42QualificationDirectLibraryUpgradeReceipt -Receipt $receipt -Target $Target
  }
  $assertions = @($receipt.assertions | ForEach-Object { [string]$_ })
  $requiredAssertions = @($script:MIR42QualificationAssertions)
  if ($Target -in $script:MIR42QualificationHistoricalTargets) { $requiredAssertions += @($script:MIR42QualificationHistoricalAssertions) }
  foreach ($required in $requiredAssertions) {
    if ($required -notin $assertions) { throw "[mir42-qualification-upgrade-assertion] $Target/$required" }
  }
  $receiptRoot = Split-Path -Parent $receiptPath
  $logs = [Collections.Generic.List[object]]::new()
  foreach ($name in @('create_log','load_log','reload_log','second_reload_log')) {
    $relative = [string]$receipt.$name
    $expectedSha = [string]$receipt.($name + '_sha256')
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '[\\/]' -or $expectedSha -notmatch '^[A-F0-9]{64}$') {
      throw "[mir42-qualification-upgrade-log-name] $Target/$name"
    }
    $logPath = Join-Path $receiptRoot $relative
    if (-not (Test-Path -LiteralPath $logPath -PathType Leaf) -or
        (Get-MIR4Sha256File -Path $logPath) -cne $expectedSha) {
      throw "[mir42-qualification-upgrade-log] $Target/$name"
    }
    $logs.Add([pscustomobject][ordered]@{ path = $relative; sha256 = $expectedSha })
  }
  return [pscustomobject][ordered]@{
    source_commit = [string]$receipt.git_commit
    receipt = [pscustomobject][ordered]@{
      path = [IO.Path]::GetFileName($receiptPath)
      sha256 = Get-MIR4Sha256File -Path $receiptPath
    }
    predecessor_receipt = [pscustomobject][ordered]@{
      version = [string]$receipt.from.version
      sha256 = [string]$receipt.from.sha256
    }
    environment = Get-MIR42QualificationEnvironment -RepoRoot $RepoRoot -Target $Target -Receipt $receipt
    assertions = @($assertions | Sort-Object -Unique -CaseSensitive)
    logs = @($logs)
    receipt_object = $receipt
  }
}

function Assert-MIR42MaintenanceReconciliationScope {
  param([Parameter(Mandatory)][string]$Scope,[Parameter(Mandatory)][object[]]$Candidates)
  if ($Scope -cne 'nine-target' -or $Candidates.Count -ne 9 -or
      @($Candidates | Where-Object { [string]$_.identity.source_version -cnotin @('4.2.1','4.2.2','4.2.3','4.3.0','4.3.1','4.4.0','4.4.2','4.5.0','4.5.2') }).Count -ne 0 -or
      @($Candidates | ForEach-Object { [string]$_.identity.source_version } | Sort-Object -Unique).Count -ne 1) {
    throw '[mir42-reconciliation-maintenance-candidate-scope]'
  }
}

function Assert-MIR42MaintenanceArchiveBindingEquality {
  param(
    [Parameter(Mandatory)][hashtable]$PredecessorZips,
    [Parameter(Mandatory)][System.Collections.IDictionary]$ArchiveBindings,
    [Parameter(Mandatory)][string[]]$Targets
  )

  $providedTargets = @($ArchiveBindings.Keys | ForEach-Object { [string]$_ })
  if ($providedTargets.Count -ne $Targets.Count -or
      @($providedTargets | Where-Object { $_ -cnotin $Targets }).Count -ne 0 -or
      @($Targets | Where-Object { -not $ArchiveBindings.Contains($_) }).Count -ne 0) {
    throw '[mir42-reconciliation-maintenance-archive-bindings]'
  }
  foreach ($target in $Targets) {
    $expected = [string]$PredecessorZips[$target]
    $provided = $ArchiveBindings[$target]
    if ($provided -isnot [string] -or [string]::IsNullOrWhiteSpace($expected) -or [string]::IsNullOrWhiteSpace($provided)) {
      throw '[mir42-reconciliation-maintenance-archive-bindings]'
    }
    try {
      $expectedPath = [IO.Path]::GetFullPath($expected)
      $providedPath = [IO.Path]::GetFullPath($provided)
    } catch {
      throw '[mir42-reconciliation-maintenance-archive-bindings]'
    }
    if (-not $expectedPath.Equals($providedPath,[StringComparison]::OrdinalIgnoreCase)) {
      throw '[mir42-reconciliation-maintenance-archive-bindings]'
    }
  }
}

function Invoke-MIR42EvidenceReconciliationShared {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][hashtable]$PredecessorZips,
    [Parameter(Mandatory)][hashtable]$UpgradeReceipts,
    [Parameter(Mandatory)][string]$OutputRoot,
    [ValidateSet('four-target','nine-target')][string]$RequiredScope,
    [string]$PublishedMaintenancePredecessorManifestPath = '',
    [System.Collections.IDictionary]$PublishedMaintenanceArchiveBindings = $null
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $currentSource = Get-MIR42QualificationCurrentSource -RepoRoot $repo
  $candidates = Get-MIR42QualificationCandidateRows -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath
  if ([string]$currentSource.commit -cne [string]$candidates[0].source.commit -or
      [string]$currentSource.tree -cne [string]$candidates[0].source.tree) {
    throw '[mir42-reconciliation-current-source-mismatch]'
  }
  $scope = [string]$candidates[0].scope
  if ($RequiredScope -and $scope -cne $RequiredScope) {
    throw '[mir42-reconciliation-entrypoint-target-scope]'
  }
  $contract = Get-MIR42QualificationScopeContract -Scope $scope
  if ($PredecessorZips.Count -ne $contract.targets.Count -or $UpgradeReceipts.Count -ne $contract.targets.Count -or
      @($PredecessorZips.Keys | Where-Object { $_ -cnotin $contract.targets }).Count -ne 0 -or
      @($UpgradeReceipts.Keys | Where-Object { $_ -cnotin $contract.targets }).Count -ne 0) {
    throw '[mir42-reconciliation-input-target-set]'
  }
  $maintenanceInputs = $null
  $maintenanceRequested = -not [string]::IsNullOrWhiteSpace($PublishedMaintenancePredecessorManifestPath)
  if ($null -ne $PublishedMaintenanceArchiveBindings -and -not $maintenanceRequested) {
    throw '[mir42-reconciliation-maintenance-archive-bindings-scope]'
  }
  if ($maintenanceRequested) {
    Assert-MIR42MaintenanceReconciliationScope -Scope $scope -Candidates $candidates
    $maintenanceSourceVersion = [string]$candidates[0].identity.source_version
    $predecessorContract = Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion $maintenanceSourceVersion
    $metadataText = (& gh api ('repos/Julesc013/more-infinite-research/releases/tags/' + $predecessorContract.source_tag) | Out-String)
    if ($LASTEXITCODE -ne 0) { throw '[mir42-reconciliation-maintenance-release-readback]' }
    $archiveBindings = $PredecessorZips
    if ($null -ne $PublishedMaintenanceArchiveBindings) {
      Assert-MIR42MaintenanceArchiveBindingEquality -PredecessorZips $PredecessorZips -ArchiveBindings $PublishedMaintenanceArchiveBindings -Targets @($contract.targets)
      $archiveBindings = $PublishedMaintenanceArchiveBindings
    }
    $maintenanceInputs = Get-MIR42PublishedMaintenancePredecessorInputs -RepoRoot $repo `
      -ManifestPath $PublishedMaintenancePredecessorManifestPath -ReleaseMetadata ($metadataText | ConvertFrom-Json -Depth 100 -DateKind String) `
      -CandidateSourceVersion $maintenanceSourceVersion -ArchiveBindings $archiveBindings
  }
  $output = Assert-MIR42QualificationOutputRoot -RepoRoot $repo -OutputRoot $OutputRoot

  $rows = [Collections.Generic.List[object]]::new()
  foreach ($candidate in $candidates) {
    $target = [string]$candidate.target
    $upgrade = Get-MIR42QualificationUpgradeReceipt -RepoRoot $repo -Target $target -Path ([string]$UpgradeReceipts[$target]) -Candidate $candidate
    if ($null -eq $maintenanceInputs -and $target -in $script:MIR42QualificationHistoricalTargets) {
      $providedPredecessor = (Resolve-Path -LiteralPath ([string]$PredecessorZips[$target])).Path
      if (-not $providedPredecessor.Equals([string]$candidate.historical.predecessor_path,[StringComparison]::OrdinalIgnoreCase)) {
        throw "[mir42-reconciliation-historical-predecessor-path] $target"
      }
    }
    $publishedInput = if ($null -ne $maintenanceInputs) { @($maintenanceInputs.targets | Where-Object { [string]$_.target -ceq $target })[0] } else { $null }
    $predecessor = Get-MIR42QualificationPredecessor -Target $target -Path ([string]$PredecessorZips[$target]) -Receipt $upgrade.receipt_object -PublishedMaintenanceInput $publishedInput
    $reconciledRow = [ordered]@{
      target = $target
      target_id = [string]$candidate.identity.target_id
      distribution_version = [string]$candidate.identity.distribution_version
      status = 'reconciled'
      source = $candidate.source
      candidate_manifest = $candidate.candidate_manifest
      candidate_target_row = $candidate.target_row
      candidate = $candidate.archive
      archive = $candidate.archive
      predecessor = $predecessor
      environment = $upgrade.environment
      harness = [pscustomobject][ordered]@{
        implementation = 'tests/runtime/Test-MIRUpgrade.ps1'
        source_commit_reported_by_receipt = $upgrade.source_commit
        source_commit_matches_candidate = ([string]$upgrade.source_commit -ceq [string]$candidate.source.commit)
        upgrade_receipt = $upgrade.receipt
        assertions = $upgrade.assertions
        logs = $upgrade.logs
      }
      qualification = 'not-performed'
      independent_verification = 'not-performed'
      technical_seal = 'not-performed'
      publication_authorized = $false
    }
    if ($null -ne $publishedInput) { $reconciledRow.published_maintenance_predecessor = $publishedInput }
    if ($target -in $script:MIR42QualificationHistoricalTargets) {
      $reconciledRow.historical = [ordered]@{
        target_record = [ordered]@{path=[string]$candidate.historical.identity.target_record_path;sha256=[string]$candidate.historical.record.record_sha256}
        terminal_seal = [ordered]@{path=('.mir/releases/terminal/seals/' + [string]$candidate.historical.record.predecessor.version + '.json');sha256=[string]$candidate.historical.seal.record_sha256}
        engine = [ordered]@{path=[string]$candidate.historical.record.engine.path;version=[string]$candidate.historical.record.engine.version;sha256=[string]$candidate.historical.record.engine.sha256}
        predecessor = [ordered]@{path=[string]$candidate.historical.record.predecessor.archive;version=[string]$candidate.historical.record.predecessor.version;sha256=[string]$candidate.historical.record.predecessor.sha256;bytes=[int64]$candidate.historical.seal.bytes;content_sha256=[string]$candidate.historical.seal.content_sha256;entry_count=[int]$candidate.historical.seal.entries}
        public_output_authorized = $false
        publication_authorized = $false
      }
    }
    $rows.Add([pscustomobject]$reconciledRow)
  }

  $result = [pscustomobject][ordered]@{
    schema = 1
    kind = if ($null -ne $maintenanceInputs) { 'MIR42NineTargetMaintenanceEvidenceReconciliationV1' } else { [string]$contract.kind }
    status = if ($null -ne $maintenanceInputs) { "MIR-$maintenanceSourceVersion-NINE-TARGET-MAINTENANCE-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED" } else { [string]$contract.status }
    reconciliation_scope = if ($null -ne $maintenanceInputs) { "The nine supplied upgrade receipts and logs match the exact candidate ZIP bytes and authenticated published $($maintenanceInputs.source_tag) predecessor archives; historical terminal records retain baseline provenance only. This command does not execute Factorio or establish release qualification." } elseif ($scope -ceq 'four-target') { 'The four supplied upgrade receipts and logs match the exact candidate ZIP bytes and supplied predecessor archives; this command does not execute Factorio or establish governed predecessor custody.' } else { 'The nine supplied upgrade receipts and logs match the exact candidate ZIP bytes, modern predecessor archives, and historical terminal-seal predecessor chains; this command does not execute Factorio or establish release qualification.' }
    source = [pscustomobject][ordered]@{
      commit = [string]$candidates[0].source.commit
      tree = [string]$candidates[0].source.tree
      package_source_sha256 = [string]$candidates[0].package_source_sha256
    }
    candidate_manifest = $candidates[0].candidate_manifest
    targets = @($rows)
    cross_target_substitution = $false
    factorio_processes = 0
    release_qualification = 'not-performed'
    independent_verification = 'not-performed'
    technical_seal = 'not-performed'
    source_freeze_authorized = $false
    signing_authorized = $false
    tagging_authorized = $false
    publication_authorized = $false
    nonclaims = @(
      'No source freeze, technical seal, protected signing, protected main promotion, maintainer gameplay GO, tagging, or publication authority is established.',
      'Caller-supplied receipts and logs are reconciled by hash only; no Factorio process or release qualification runs in this command.',
      'Receipt source commits may differ from the current candidate source. The archive-byte match does not confer source-bound runtime proof.',
      'The supplied predecessor archives have no governed direct-predecessor custody assertion in this record.'
    )
    record_sha256 = ''
  }
  if ($null -ne $maintenanceInputs) {
    $result | Add-Member -NotePropertyName published_maintenance_predecessor -NotePropertyValue $maintenanceInputs
    $result.nonclaims = @($result.nonclaims | Where-Object { $_ -cne 'The supplied predecessor archives have no governed direct-predecessor custody assertion in this record.' })
    $result.nonclaims += 'Published predecessor custody is authenticated separately; its unsigned source and historical NOT RUN fields grant no new candidate qualification.'
  }
  $result | Add-Member -NotePropertyName ([string]$contract.target_requirement) -NotePropertyValue $true
  $path = Resolve-MIR4ArtifactPath -OutputRoot $output -RelativePath 'evidence-reconciliation.json'
  Write-MIR4BootstrapRecord -Record $result -Path $path | Out-Null
  return $result
}

function Invoke-MIR42FourTargetEvidenceReconciliation {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$F210PredecessorZip,
    [Parameter(Mandatory)][string]$F200PredecessorZip,
    [Parameter(Mandatory)][string]$F110PredecessorZip,
    [Parameter(Mandatory)][string]$F100PredecessorZip,
    [Parameter(Mandatory)][string]$F210UpgradeReceipt,
    [Parameter(Mandatory)][string]$F200UpgradeReceipt,
    [Parameter(Mandatory)][string]$F110UpgradeReceipt,
    [Parameter(Mandatory)][string]$F100UpgradeReceipt,
    [Parameter(Mandatory)][string]$OutputRoot
  )
  return Invoke-MIR42EvidenceReconciliationShared -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath -PredecessorZips @{
    f210=$F210PredecessorZip;f200=$F200PredecessorZip;f110=$F110PredecessorZip;f100=$F100PredecessorZip
  } -UpgradeReceipts @{
    f210=$F210UpgradeReceipt;f200=$F200UpgradeReceipt;f110=$F110UpgradeReceipt;f100=$F100UpgradeReceipt
  } -OutputRoot $OutputRoot
}

function Invoke-MIR42NineTargetEvidenceReconciliation {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][hashtable]$PredecessorZips,
    [Parameter(Mandatory)][hashtable]$UpgradeReceipts,
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$PublishedMaintenancePredecessorManifestPath = '',
    [System.Collections.IDictionary]$PublishedMaintenanceArchiveBindings = $null
  )
  $manifest = Read-MIR42QualificationBootstrapRecord -Path $CandidateManifestPath -Code 'mir42-reconciliation-entrypoint-candidate'
  if ((Get-MIR42QualificationTargetScope -Rows @($manifest.targets) -Code 'mir42-reconciliation-entrypoint') -cne 'nine-target') {
    throw '[mir42-reconciliation-entrypoint-target-scope]'
  }
  return Invoke-MIR42EvidenceReconciliationShared -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath -PredecessorZips $PredecessorZips -UpgradeReceipts $UpgradeReceipts -OutputRoot $OutputRoot -RequiredScope 'nine-target' -PublishedMaintenancePredecessorManifestPath $PublishedMaintenancePredecessorManifestPath -PublishedMaintenanceArchiveBindings $PublishedMaintenanceArchiveBindings
}

$script:MIR42ReleaseAcceptanceCriteria = @(
  'fresh-exact-loads', 'settings-profile-continuity', 'research-progression', 'migrations-two-reload',
  'compatibility-canaries', 'target-omissions', 'performance-telemetry', 'package-exclusion',
  'deterministic-reconstruction'
)


$script:MIR430EmergencyPerformanceAuthorityPath = 'governance/repository/mir430-emergency-performance-v1.json'
$script:MIR430EmergencyPerformanceStages = @('settings','data','data-updates','data-final-fixes')

function Assert-MIR430PerformancePropertyNames {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string[]]$Expected,[Parameter(Mandatory)][string]$Code)
  $actual = @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
  if ($actual.Count -ne $Expected.Count -or @($actual | Where-Object { $_ -cnotin $Expected }).Count -ne 0) {
    throw "[$Code]"
  }
}

function Get-MIR430PerformanceTextSha256 {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($Text)))
}

function Get-MIR430EmergencyPerformanceAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authorityPath = Join-Path $repo $script:MIR430EmergencyPerformanceAuthorityPath
  $authority = Read-MIR42QualificationBootstrapRecord -Path $authorityPath -Code 'mir430-performance-authority'
  $authoritySchema = Join-Path $repo 'spec/schemas/mir430-emergency-performance-v1.schema.json'
  if (-not (Test-Path -LiteralPath $authoritySchema -PathType Leaf) -or -not ((Get-Content -Raw -LiteralPath $authorityPath) | Test-Json -SchemaFile $authoritySchema -ErrorAction SilentlyContinue)) {
    throw '[mir430-performance-authority-schema]'
  }
  Assert-MIR430PerformancePropertyNames -Value $authority -Expected @(
    'schema','kind','authority_id','source_version','status','max_mir_startup_seconds','minimum_samples_per_profile',
    'compiler_profile','default_settings_mode','catalogue_definition_capture_kind','required_stages','required_profiles','allowed_observer','ordinary_menu_status','library_first_use_status',
    'relative_overhead_status','timeout_status','reporter_environment_status','basis','release_deadline_utc','record_sha256'
  ) -Code 'mir430-performance-authority-shape'
  if ([int]$authority.schema -ne 1 -or [string]$authority.kind -cne 'MIR430EmergencyPerformanceAcceptanceV1' -or
      [string]$authority.authority_id -cne 'MIR430-EMERGENCY-PERFORMANCE-V1' -or [string]$authority.source_version -cne '4.3.0' -or
      [string]$authority.status -cne 'adopted-maintainer-emergency-acceptance-not-evidence' -or
      [double]$authority.max_mir_startup_seconds -ne 60.0 -or [int]$authority.minimum_samples_per_profile -ne 1 -or
      [string]$authority.compiler_profile -cne 'full' -or [string]$authority.default_settings_mode -cne 'canonical-absent-default' -or
      [string]$authority.catalogue_definition_capture_kind -cne 'MIR430FullDefaultPrototypeCaptureV1' -or
      (@($authority.required_stages | ForEach-Object { [string]$_ }) -join '|') -cne ($script:MIR430EmergencyPerformanceStages -join '|')) {
    throw '[mir430-performance-authority-binding]'
  }
  Assert-MIR430PerformancePropertyNames -Value $authority.allowed_observer -Expected @('name','version','archive_sha256','source_files') -Code 'mir430-performance-authority-observer-shape'
  if ([string]$authority.allowed_observer.name -cne 'mir430-compiler-profile-ablation' -or
      [string]$authority.allowed_observer.version -cne '1.0.4' -or [string]$authority.allowed_observer.archive_sha256 -notmatch '^[A-F0-9]{64}$' -or
      @($authority.allowed_observer.source_files).Count -ne 4) {
    throw '[mir430-performance-authority-observer-binding]'
  }
  foreach ($sourceFile in @($authority.allowed_observer.source_files)) {
    Assert-MIR430PerformancePropertyNames -Value $sourceFile -Expected @('path','bytes','sha256') -Code 'mir430-performance-authority-observer-source-shape'
    if ([string]$sourceFile.path -notmatch '^fixtures/assert-mir430-startup-work/[a-z-]+[.](?:json|lua)$' -or [int64]$sourceFile.bytes -le 0 -or [string]$sourceFile.sha256 -notmatch '^[A-F0-9]{64}$') {
      throw '[mir430-performance-authority-observer-source-binding]'
    }
    $sourcePath = Join-Path $repo ([string]$sourceFile.path)
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or [int64](Get-Item -LiteralPath $sourcePath).Length -ne [int64]$sourceFile.bytes -or
        (Get-MIR4Sha256File -Path $sourcePath) -cne [string]$sourceFile.sha256) {
      throw '[mir430-performance-authority-observer-source-file]'
    }
  }
  $profiles = @($authority.required_profiles)
  if ($profiles.Count -ne 3 -or (@($profiles | ForEach-Object { [string]$_.id }) -join '|') -cne 'f200-galore-space-age|f200-bob-angel|f200-omni-bob-angel-46') {
    throw '[mir430-performance-authority-profiles]'
  }
  $resolvedProfiles = [Collections.Generic.List[object]]::new()
  foreach ($required in $profiles) {
    Assert-MIR430PerformancePropertyNames -Value $required -Expected @('id','target','definition') -Code 'mir430-performance-authority-profile-shape'
    Assert-MIR430PerformancePropertyNames -Value $required.definition -Expected @('path','bytes','sha256') -Code 'mir430-performance-authority-profile-definition-shape'
    if ([string]$required.target -cne 'f200' -or [string]$required.definition.path -notmatch '^fixtures/run-profiles/mir430-startup-[a-z0-9-]+-f200[.]json$' -or
        [int64]$required.definition.bytes -le 0 -or [string]$required.definition.sha256 -notmatch '^[A-F0-9]{64}$') {
      throw "[mir430-performance-authority-profile-binding] $([string]$required.id)"
    }
    $definitionPath = Join-Path $repo ([string]$required.definition.path)
    if (-not (Test-Path -LiteralPath $definitionPath -PathType Leaf) -or [int64](Get-Item -LiteralPath $definitionPath).Length -ne [int64]$required.definition.bytes -or
        (Get-MIR4Sha256File -Path $definitionPath) -cne [string]$required.definition.sha256) {
      throw "[mir430-performance-authority-profile-file] $([string]$required.id)"
    }
    $profileSchema = Join-Path $repo 'spec/schemas/mir430-named-startup-stress-profile-v1.schema.json'
    if (-not (Test-Path -LiteralPath $profileSchema -PathType Leaf) -or -not ((Get-Content -Raw -LiteralPath $definitionPath) | Test-Json -SchemaFile $profileSchema -ErrorAction SilentlyContinue)) {
      throw "[mir430-performance-authority-profile-schema] $([string]$required.id)"
    }
    try { $definition = Get-Content -Raw -LiteralPath $definitionPath | ConvertFrom-Json -Depth 100 -DateKind String }
    catch { throw "[mir430-performance-authority-profile-json] $([string]$required.id)" }
    Assert-MIR430PerformancePropertyNames -Value $definition -Expected @('schema','kind','id','target','status','engine','mods','archive_pins','builtin_pins','claim_scope') -Code 'mir430-performance-profile-shape'
    Assert-MIR430PerformancePropertyNames -Value $definition.engine -Expected @('version','sha256') -Code 'mir430-performance-profile-engine-shape'
    if ([int]$definition.schema -ne 1 -or [string]$definition.kind -cne 'MIR430NamedStartupStressProfileV1' -or
        [string]$definition.id -cne [string]$required.id -or [string]$definition.target -cne [string]$required.target -or
        [string]$definition.status -cne 'acquired-exact-selection-not-native-qualified' -or [string]$definition.engine.version -notmatch '^2[.]0[.]\d+$' -or
        [string]$definition.engine.sha256 -notmatch '^[A-F0-9]{64}$' -or @($definition.mods).Count -eq 0 -or
        [string]$definition.claim_scope -cne 'specified-available-inputs-not-reporter-313-mod-environment') {
      throw "[mir430-performance-profile-binding] $([string]$required.id)"
    }
    $resolvedProfiles.Add([pscustomobject][ordered]@{id=[string]$required.id;target=[string]$required.target;definition=$required.definition;profile=$definition})
  }
  return [pscustomobject][ordered]@{path=$authorityPath;sha256=(Get-MIR4Sha256File -Path $authorityPath);record=$authority;profiles=@($resolvedProfiles)}
}

function Resolve-MIR430PerformanceEvidenceFile {
  param([Parameter(Mandatory)][string]$ObservationPath,[Parameter(Mandatory)]$Descriptor,[Parameter(Mandatory)][string]$Code)

  Assert-MIR430PerformancePropertyNames -Value $Descriptor -Expected @('path','sha256') -Code "$Code-shape"
  if ([string]::IsNullOrWhiteSpace([string]$Descriptor.path) -or [string]$Descriptor.sha256 -notmatch '^[A-F0-9]{64}$') { throw "[$Code-binding]" }
  $root = Split-Path -Parent ((Resolve-Path -LiteralPath $ObservationPath).Path)
  $candidate = if ([IO.Path]::IsPathRooted([string]$Descriptor.path)) { [string]$Descriptor.path } else { Join-Path $root ([string]$Descriptor.path) }
  if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw "[$Code-missing]" }
  $path = (Resolve-Path -LiteralPath $candidate).Path
  if ((Get-MIR4Sha256File -Path $path) -cne [string]$Descriptor.sha256) { throw "[$Code-hash]" }
  return $path
}

function Get-MIR430PerformanceLedgerCompletion {
  param([Parameter(Mandatory)][string]$Path)

  $item = Get-Item -LiteralPath $Path
  if ($item.Length -le 0 -or $item.Length -gt 16MB) { throw '[mir430-performance-resource-ledger-size]' }
  $lines = @(Get-Content -LiteralPath $Path)
  if ($lines.Count -eq 0 -or $lines.Count -gt 10000) { throw '[mir430-performance-resource-ledger-lines]' }
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { throw '[mir430-performance-resource-ledger-json]' }
    try { $rows.Add(($line | ConvertFrom-Json -Depth 50 -DateKind String)) }
    catch { throw '[mir430-performance-resource-ledger-json]' }
  }
  foreach ($row in $rows) {
    if (($row.PSObject.Properties.Name -contains 'timed_out' -and [bool]$row.timed_out) -or
        ($row.PSObject.Properties.Name -contains 'phase' -and [string]$row.phase -in @('interrupted','refused','timeout','timed-out')) -or
        ($row.PSObject.Properties.Name -contains 'error' -and -not [string]::IsNullOrWhiteSpace([string]$row.error))) {
      throw '[mir430-performance-resource-ledger-incomplete]'
    }
  }
  $final = $rows[$rows.Count - 1]
  if ([string]$final.phase -cne 'completed' -or [int]$final.exit_code -ne 0 -or
      -not ($final.PSObject.Properties.Name -contains 'peak_working_set_bytes') -or -not ($final.PSObject.Properties.Name -contains 'peak_sampled_private_bytes')) {
    throw '[mir430-performance-resource-ledger-completion]'
  }
}

function Get-MIR430PerformanceParsedStages {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string[]]$Stages)

  $item = Get-Item -LiteralPath $Path
  if ($item.Length -le 0 -or $item.Length -gt 64MB) { throw '[mir430-performance-log-size]' }
  $text = Get-Content -Raw -LiteralPath $Path
  $marker = [regex]::new('(?m)^\s*(?<seconds>[0-9]+(?:\.[0-9]+)?)\s+.*\[more-infinite-research\] startup-stage=(?<stage>settings|data|data-updates|data-final-fixes) (?<edge>begin|end)\s*$')
  $events = @($marker.Matches($text))
  if ($events.Count -ne ($Stages.Count * 2)) { throw '[mir430-performance-stage-marker-count]' }
  $profileMarker = [regex]::new('(?m)^\s*[0-9]+(?:\.[0-9]+)?\s+.*\[MIR430-ABLATION\] actual-profile=full\s*$')
  if ($profileMarker.Matches($text).Count -ne 1) { throw '[mir430-performance-full-selection]' }
  $defaultMarker = [regex]::new('(?m)^\s*[0-9]+(?:\.[0-9]+)?\s+.*\[MIR430-ABLATION\] declared-default=full\s*$')
  if ($defaultMarker.Matches($text).Count -ne 1) { throw '[mir430-performance-default-selection]' }
  $parsed = [Collections.Generic.List[object]]::new()
  $eventIndex = 0
  $last = -1.0
  foreach ($stage in $Stages) {
    $begin = $events[$eventIndex];$end = $events[$eventIndex + 1];$eventIndex += 2
    if ($begin.Groups['stage'].Value -cne $stage -or $begin.Groups['edge'].Value -cne 'begin' -or
        $end.Groups['stage'].Value -cne $stage -or $end.Groups['edge'].Value -cne 'end') {
      throw '[mir430-performance-stage-order]'
    }
    $beginSeconds = 0.0;$endSeconds = 0.0
    if (-not [double]::TryParse($begin.Groups['seconds'].Value,[Globalization.NumberStyles]::AllowDecimalPoint,[Globalization.CultureInfo]::InvariantCulture,[ref]$beginSeconds) -or
        -not [double]::TryParse($end.Groups['seconds'].Value,[Globalization.NumberStyles]::AllowDecimalPoint,[Globalization.CultureInfo]::InvariantCulture,[ref]$endSeconds) -or
        [double]::IsNaN($beginSeconds) -or [double]::IsInfinity($beginSeconds) -or [double]::IsNaN($endSeconds) -or [double]::IsInfinity($endSeconds) -or
        $beginSeconds -lt $last -or $endSeconds -lt $beginSeconds) {
      throw '[mir430-performance-stage-time]'
    }
    $last = $endSeconds
    $parsed.Add([pscustomobject][ordered]@{stage=$stage;begin_seconds=$beginSeconds;end_seconds=$endSeconds;elapsed_seconds=($endSeconds - $beginSeconds)})
  }
  $technologyMarker = [regex]::new('(?m)^\s*[0-9]+(?:\.[0-9]+)?\s+.*\[MIR430-ABLATION\] technology-names=(?<names>.*)\s*$')
  $technologyLines = @($technologyMarker.Matches($text))
  if ($technologyLines.Count -ne 1) { throw '[mir430-performance-generated-technology-marker]' }
  $technologyNames = @([regex]::Matches($technologyLines[0].Groups['names'].Value,'["''](?<name>[^"'']+)["'']') | ForEach-Object { [string]$_.Groups['name'].Value } | Sort-Object -Unique)
  return [pscustomobject][ordered]@{
    stages = @($parsed)
    technology_names = @($technologyNames)
    technology_ids_sha256 = Get-MIR430PerformanceTextSha256 -Text ($technologyNames -join "`n")
  }
}

function Get-MIR430FullSnapshotProjection {
  param(
    [Parameter(Mandatory)][string]$ObservationPath,[Parameter(Mandatory)]$Descriptor,
    [Parameter(Mandatory)][ValidateSet('source','upgrade','candidate')][string]$Stage,
    [Parameter(Mandatory)][string[]]$ExpectedActiveSelection,[Parameter(Mandatory)][string]$ExpectedCompilerProfile,
    [Parameter(Mandatory)][string]$Code,
    [ValidateSet('upgrade-preservation-proof','matched-startup-capture')][string]$CaptureMode = 'upgrade-preservation-proof',
    [string]$ExpectedPackageVersion = ''
  )

  Assert-MIR430PerformancePropertyNames -Value $Descriptor -Expected @('path','sha256','stage') -Code "$Code-raw-snapshot-shape"
  if ([string]$Descriptor.stage -cne $Stage) { throw "[$Code-raw-snapshot-stage]" }
  $path = Resolve-MIR430PerformanceEvidenceFile -ObservationPath $ObservationPath -Descriptor ([pscustomobject][ordered]@{path=[string]$Descriptor.path;sha256=[string]$Descriptor.sha256}) -Code "$Code-raw-snapshot"
  try { $snapshot = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100 -DateKind String } catch { throw "[$Code-raw-snapshot-json]" }
  $requiredSnapshotFields = if ($CaptureMode -ceq 'matched-startup-capture') {
    @('schema','kind','stage','package_version','active_mods','forces')
  } else {
    @('from_version','to_version','stage','active_mods','forces')
  }
  foreach ($field in $requiredSnapshotFields) {
    if ($snapshot.PSObject.Properties.Name -notcontains $field) { throw "[$Code-raw-snapshot-shape]" }
  }
  if ($CaptureMode -ceq 'matched-startup-capture' -and ([int]$snapshot.schema -ne 1 -or [string]$snapshot.kind -cne 'MIR430FullTechnologySnapshotV1' -or [string]$snapshot.package_version -cne $ExpectedPackageVersion)) {
    throw "[$Code-raw-snapshot-binding]"
  }
  if ([string]$snapshot.stage -cne $Stage -or $null -eq $snapshot.forces -or $snapshot.forces.PSObject.Properties.Name -notcontains 'player') { throw "[$Code-raw-snapshot-binding]" }
  $active = @($snapshot.active_mods.PSObject.Properties | ForEach-Object { [string]$_.Name + '@' + [string]$_.Value } | Sort-Object)
  if (($active -join '|') -cne (@($ExpectedActiveSelection | Sort-Object) -join '|')) { throw "[$Code-raw-snapshot-active-mods]" }
  $force = $snapshot.forces.player
  foreach ($field in @('technologies','settings')) {
    if ($force.PSObject.Properties.Name -notcontains $field) { throw "[$Code-raw-snapshot-force]" }
  }
  $actualCompilerProfile = if ($force.settings.PSObject.Properties.Name -contains 'mir-compiler-profile') { [string]$force.settings.'mir-compiler-profile' } else { 'absent' }
  if ($actualCompilerProfile -cne $ExpectedCompilerProfile) { throw "[$Code-raw-snapshot-settings]" }
  $settingsRows = [ordered]@{}
  foreach ($setting in @($force.settings.PSObject.Properties | Sort-Object Name)) {
    if ([string]$setting.Name -cne 'mir-compiler-profile') { $settingsRows[[string]$setting.Name] = $setting.Value }
  }
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($property in @($force.technologies.PSObject.Properties | Sort-Object Name)) {
    $technology = $property.Value
    foreach ($field in @('enabled','visible_when_disabled','prototype')) {
      if ($technology.PSObject.Properties.Name -notcontains $field) { throw "[$Code-raw-snapshot-technology]" }
    }
    $prototype = $technology.prototype
    foreach ($field in @('order','hidden','max_level','prerequisites','ingredients','effects','unit_count','unit_count_formula','unit_energy')) {
      if ($prototype.PSObject.Properties.Name -notcontains $field) { throw "[$Code-raw-snapshot-prototype]" }
    }
    $effects = @($prototype.effects | ForEach-Object { ConvertTo-MIR4BootstrapCanonicalJson -Value $_ } | Sort-Object)
    $ingredients = @($prototype.ingredients | ForEach-Object { ConvertTo-MIR4BootstrapCanonicalJson -Value $_ } | Sort-Object)
    $rows.Add([pscustomobject][ordered]@{
      id=[string]$property.Name
      order=[string]$prototype.order
      hidden=[bool]$prototype.hidden
      effects=@($effects)
      prerequisites=@($prototype.prerequisites | ForEach-Object { [string]$_ } | Sort-Object)
      science_ingredients=@($ingredients)
      unit_count=$prototype.unit_count
      unit_count_formula=$prototype.unit_count_formula
      unit_time=$prototype.unit_energy
      max_level=$prototype.max_level
      enabled=[bool]$technology.enabled
      visible_when_disabled=[bool]$technology.visible_when_disabled
    })
  }
  if ($rows.Count -eq 0) { throw "[$Code-raw-snapshot-technologies]" }
  $canonical = ConvertTo-MIR4BootstrapCanonicalJson -Value @($rows)
  return [pscustomobject][ordered]@{
    path=$path;sha256=(Get-MIR4Sha256File -Path $path);snapshot=$snapshot;technology_ids=@($rows | ForEach-Object { [string]$_.id });technology_ids_sha256=(Get-MIR430PerformanceTextSha256 -Text ((@($rows | ForEach-Object { [string]$_.id }) -join "`n")));semantic_definitions_sha256=(Get-MIR430PerformanceTextSha256 -Text $canonical);settings_sha256=(Get-MIR430PerformanceTextSha256 -Text (ConvertTo-MIR4BootstrapCanonicalJson -Value $settingsRows))
  }
}

function Get-MIR430PerformanceActivationSelection {
  param([Parameter(Mandatory)]$Activation,[Parameter(Mandatory)][string]$Code)
  if ($Activation.PSObject.Properties.Name -notcontains 'selected') { throw "[$Code-shape]" }
  $rows = @($Activation.selected)
  if ($rows.Count -eq 0) { throw "[$Code-empty]" }
  $selection = @(
    foreach ($row in $rows) {
      if ($null -eq $row -or $row.PSObject.Properties.Name -notcontains 'name' -or $row.PSObject.Properties.Name -notcontains 'version' -or
          [string]::IsNullOrWhiteSpace([string]$row.name) -or [string]::IsNullOrWhiteSpace([string]$row.version)) {
        throw "[$Code-shape]"
      }
      [string]$row.name + '@' + [string]$row.version
    }
  )
  if (@($selection | Sort-Object -Unique).Count -ne $selection.Count) { throw "[$Code-duplicate]" }
  return @($selection | Sort-Object)
}

function Assert-MIR430MatchedStartupCaptureRun {
  param(
    [Parameter(Mandatory)][string]$ObservationPath,[Parameter(Mandatory)]$Descriptor,
    [Parameter(Mandatory)]$Expected,[Parameter(Mandatory)]$CandidateTarget,[Parameter(Mandatory)]$Authority,
    [Parameter(Mandatory)][string[]]$BaselineSelection,[Parameter(Mandatory)][string[]]$CandidateSelection,
    [Parameter(Mandatory)][string]$BaselineRawPath,[Parameter(Mandatory)][string]$CandidateRawPath,
    [Parameter(Mandatory)][string]$Code
  )

  Assert-MIR430PerformancePropertyNames -Value $Descriptor -Expected @('path','sha256','source_sample_label','candidate_sample_label') -Code "$Code-matched-run-shape"
  $path = Resolve-MIR430PerformanceEvidenceFile -ObservationPath $ObservationPath -Descriptor ([pscustomobject][ordered]@{path=[string]$Descriptor.path;sha256=[string]$Descriptor.sha256}) -Code "$Code-matched-run"
  try { $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100 -DateKind String } catch { throw "[$Code-matched-run-json]" }
  foreach ($field in @('kind','status','mode','source_observation','factorio','inputs','resource_context','samples')) {
    if ($record.PSObject.Properties.Name -notcontains $field) { throw "[$Code-matched-run-shape]" }
  }
  if ([string]$record.kind -cne 'MIRDirectLibraryStartupMeasurementV1' -or [string]$record.status -cne 'completed' -or [string]$record.mode -cne 'matched-three-input' -or
      [string]$record.factorio.sha256 -cne [string]$Expected.profile.engine.sha256 -or
      [string]$record.factorio.base_version -cne [string]$Expected.profile.engine.version -or
      [string]$record.inputs.published_422.archive.version -cne '4.2.20002' -or
      [string]$record.inputs.published_422.archive.sha256 -cne '14C2B23E0F4657F9F79585A982639463678D640C04916FEECC365D93B6894A65' -or
      [string]$record.inputs.candidate.source_version -cne [string]$CandidateTarget.source_version -or
      [string]$record.inputs.candidate.archive.sha256 -cne [string]$CandidateTarget.archive.sha256 -or
      [string]$record.inputs.candidate.materialization.source_version -cne [string]$CandidateTarget.source_version -or
      [string]$record.inputs.candidate.materialization.archive_sha256 -cne [string]$CandidateTarget.archive.sha256 -or
      [string]$record.inputs.candidate.materialization.package_source_sha256 -cne [string]$CandidateTarget.package_source_sha256 -or
      [string]$record.source_observation.requested_commit -cne [string]$Candidate.source.commit -or
      [string]$record.source_observation.head_commit -cne [string]$Candidate.source.commit) {
    throw "[$Code-matched-run-binding]"
  }
  $completedProcesses = @($record.resource_context.processes | Where-Object { [string]$_.status -ceq 'passed' -and [bool]$_.result.passed -and [int]$_.result.exit_code -eq 0 -and -not [bool]$_.result.timed_out })
  if ($completedProcesses.Count -lt 2) { throw "[$Code-matched-run-completion]" }

  $bindSample = {
    param([string]$Label,[string]$Stage,[string]$ExpectedVersion,[string[]]$ExpectedSelection,[string]$ExpectedRawPath)
    $matches = @($record.samples | Where-Object { [string]$_.label -ceq $Label -and [string]$_.cache_state -ceq 'changed-configuration' })
    if ($matches.Count -ne 1) { throw "[$Code-matched-run-sample]" }
    $sample = $matches[0]
    $selection = @($sample.loaded_selection | ForEach-Object { [string]$_ } | Sort-Object)
    if ([int]$sample.exit_code -ne 0 -or [string]$sample.endpoint_class -cne 'headless-create-diagnostic' -or
        ($selection -join '|') -cne (@($ExpectedSelection | Sort-Object) -join '|')) {
      throw "[$Code-matched-run-sample]"
    }
    $runRoot = [string]$sample.run_relative_path
    $log = Resolve-MIR430PerformanceInvocationArtifact -InvocationPath $path -RelativePath ($runRoot + '/' + [string]$sample.log) -Code "$Code-matched-run-log"
    $config = Resolve-MIR430PerformanceInvocationArtifact -InvocationPath $path -RelativePath ($runRoot + '/' + [string]$sample.execution_controls.config.path) -Code "$Code-matched-run-config"
    $identity = Get-MIR430PerformanceLogIdentity -Path $log -ObserverName ([string]$Authority.record.allowed_observer.name) -Code "$Code-matched-run-log"
    if ([string]$identity.engine_version -cne [string]$Expected.profile.engine.version -or ($identity.active_selection -join '|') -cne ($selection -join '|')) { throw "[$Code-matched-run-log]" }
    $text = Get-Content -Raw -LiteralPath $log
    $profile = if ($ExpectedVersion -ceq '4.2.20002') {'absent'} else {[string]$Authority.record.compiler_profile}
    if ([regex]::Matches($text,'(?m)^\s*[0-9]+(?:\.[0-9]+)?\s+.*\[MIR430-ABLATION\] actual-profile=' + [regex]::Escape($profile) + '\s*$').Count -ne 1 -or
        [regex]::Matches($text,'(?m)^\s*[0-9]+(?:\.[0-9]+)?\s+.*\[MIR430-ABLATION\] declared-default=' + [regex]::Escape($profile) + '\s*$').Count -ne 1 -or
        [regex]::Matches($text,'(?m)^\s*.*\[MIR430-CAPTURE\] stage=' + [regex]::Escape($Stage) + '\s+package=' + [regex]::Escape($ExpectedVersion) + '\s+technologies=[0-9]+\s+output=mir430-full-technology-' + [regex]::Escape($Stage) + '[.]json\s*$').Count -ne 1) {
      throw "[$Code-matched-run-capture-log]"
    }
    $configText = Get-Content -Raw -LiteralPath $config
    $writeData = [regex]::Match($configText,'(?m)^write-data=(?<path>[^\r\n]+)\s*$')
    if (-not $writeData.Success) { throw "[$Code-matched-run-config]" }
    $expectedRaw = [IO.Path]::GetFullPath((Join-Path $writeData.Groups['path'].Value ('script-output/mir430-full-technology-' + $Stage + '.json')))
    if ([IO.Path]::GetFullPath($ExpectedRawPath) -cne $expectedRaw) { throw "[$Code-matched-run-capture-path]" }
  }
  & $bindSample ([string]$Descriptor.source_sample_label) 'source' '4.2.20002' $BaselineSelection $BaselineRawPath
  & $bindSample ([string]$Descriptor.candidate_sample_label) 'candidate' ([string]$CandidateTarget.distribution_version) $CandidateSelection $CandidateRawPath
  return [pscustomobject][ordered]@{path=$path;record=$record}
}

function New-MIR430MatchedStartupCaptureRecord {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$MeasurementPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)]$Candidate,
    [Parameter(Mandatory)][string]$ProfileId,
    [Parameter(Mandatory)][string]$Code
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $measurement = (Resolve-Path -LiteralPath $MeasurementPath).Path
  $resultPath = Join-Path $measurement 'result.json'
  if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { throw "[$Code-matched-run-missing]" }
  $output = [IO.Path]::GetFullPath($OutputPath)
  if ((Split-Path -Parent $output) -cne $measurement) { throw "[$Code-output-path]" }
  $authority = Get-MIR430EmergencyPerformanceAuthority -RepoRoot $repo
  $expected = @($authority.profiles | Where-Object { [string]$_.id -ceq $ProfileId })
  if ($expected.Count -ne 1) { throw "[$Code-profile]" }
  $expected = $expected[0]
  $target = Get-MIR430PerformanceCandidateTarget -Candidate $Candidate -Target ([string]$expected.target) -Code $Code
  $candidateSelection = @(Get-MIR430ExpectedProfileLoadedSelection -ProfileDefinition $expected.profile -CandidateTarget $target -Authority $authority -Code $Code)
  $baselineSelection = @($candidateSelection | ForEach-Object { if ($_ -match '^more-infinite-research@') { 'more-infinite-research@4.2.20002' } else { $_ } })
  try { $result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json -Depth 100 -DateKind String } catch { throw "[$Code-matched-run-json]" }
  $sourceSamples = @($result.samples | Where-Object { [string]$_.label -ceq 'released-4.2.2' -and [string]$_.cache_state -ceq 'changed-configuration' })
  $candidateSamples = @($result.samples | Where-Object { [string]$_.label -ceq 'candidate-4.3.0' -and [string]$_.cache_state -ceq 'changed-configuration' })
  if ($sourceSamples.Count -ne 1 -or $candidateSamples.Count -ne 1) { throw "[$Code-matched-run-sample]" }
  $rawPathFor = {
    param($Sample,[string]$Stage)
    $run = Join-Path $measurement ([string]$Sample.run_relative_path)
    $config = Join-Path $run ([string]$Sample.execution_controls.config.path)
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { throw "[$Code-matched-run-config]" }
    $writeData = [regex]::Match((Get-Content -Raw -LiteralPath $config),'(?m)^write-data=(?<path>[^\r\n]+)\s*$')
    if (-not $writeData.Success) { throw "[$Code-matched-run-config]" }
    return [IO.Path]::GetFullPath((Join-Path $writeData.Groups['path'].Value ('script-output/mir430-full-technology-' + $Stage + '.json')))
  }
  $sourceRaw = & $rawPathFor $sourceSamples[0] 'source'
  $candidateRaw = & $rawPathFor $candidateSamples[0] 'candidate'
  foreach ($path in @($sourceRaw,$candidateRaw)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[$Code-raw-snapshot-missing]" } }
  $relative = { param([string]$Path) return [IO.Path]::GetRelativePath($measurement,$Path).Replace('\','/') }
  $upstream = @($candidateSelection | Where-Object { $_ -notmatch '^more-infinite-research@' -and $_ -notmatch ('^' + [regex]::Escape([string]$authority.record.allowed_observer.name) + '@') })
  $upstreamSha = Get-MIR430PerformanceTextSha256 -Text ($upstream -join "`n")
  $capture = [pscustomobject][ordered]@{
    schema = 1
    kind = [string]$authority.record.catalogue_definition_capture_kind
    status = 'completed'
    source = $Candidate.source
    candidate_manifest = $Candidate.candidate_manifest
    profile = [ordered]@{ id=[string]$expected.id; target=[string]$expected.target; definition=$expected.definition; engine=$expected.profile.engine; loaded_selection=$candidateSelection }
    compiler_profile = [string]$authority.record.compiler_profile
    settings = [ordered]@{ kind=[string]$authority.record.default_settings_mode }
    capture_mode = 'matched-startup-capture'
    baseline = [ordered]@{
      source_version='4.2.2'; distribution_version='4.2.20002'; profile_definition_sha256=[string]$expected.definition.sha256; engine_sha256=[string]$expected.profile.engine.sha256
      settings_kind=[string]$authority.record.default_settings_mode; compiler_profile_marker='absent'; upstream_selection_sha256=$upstreamSha
      raw_snapshot=[ordered]@{path=(& $relative $sourceRaw);sha256=(Get-MIR4Sha256File -Path $sourceRaw);stage='source'}
    }
    candidate_catalogue = [ordered]@{
      compiler_profile_marker=[string]$authority.record.compiler_profile; settings_kind=[string]$authority.record.default_settings_mode; upstream_selection_sha256=$upstreamSha
      raw_snapshot=[ordered]@{path=(& $relative $candidateRaw);sha256=(Get-MIR4Sha256File -Path $candidateRaw);stage='candidate'}
    }
    native_run = [ordered]@{path='result.json';sha256=(Get-MIR4Sha256File -Path $resultPath);source_sample_label='released-4.2.2';candidate_sample_label='candidate-4.3.0'}
    record_sha256 = ''
  }
  Write-MIR4BootstrapRecord -Record $capture -Path $output | Out-Null
  $descriptor = [pscustomobject][ordered]@{path=[IO.Path]::GetFileName($output);sha256=(Get-MIR4Sha256File -Path $output);record_sha256=[string]$capture.record_sha256}
  return Assert-MIR430FullCatalogueDefinitionCapture -ObservationPath $output -Descriptor $descriptor -Profile $expected -Expected $expected -Candidate $Candidate -CandidateTarget $target -Authority $authority -Code $Code
}

function Assert-MIR430FullCatalogueDefinitionCapture {
  param(
    [Parameter(Mandatory)][string]$ObservationPath,[Parameter(Mandatory)]$Descriptor,
    [Parameter(Mandatory)]$Profile,[Parameter(Mandatory)]$Expected,[Parameter(Mandatory)]$Candidate,
    [Parameter(Mandatory)]$CandidateTarget,[Parameter(Mandatory)]$Authority,[Parameter(Mandatory)][string]$Code
  )

  Assert-MIR430PerformancePropertyNames -Value $Descriptor -Expected @('path','sha256','record_sha256') -Code "$Code-catalogue-capture-shape"
  $capturePath = Resolve-MIR430PerformanceEvidenceFile -ObservationPath $ObservationPath -Descriptor ([pscustomobject][ordered]@{path=[string]$Descriptor.path;sha256=[string]$Descriptor.sha256}) -Code "$Code-catalogue-capture"
  $capture = Read-MIR42QualificationBootstrapRecord -Path $capturePath -Code "$Code-catalogue-capture"
  Assert-MIR430PerformancePropertyNames -Value $capture -Expected @(
    'schema','kind','status','source','candidate_manifest','profile','compiler_profile','settings','capture_mode','baseline','candidate_catalogue','native_run','record_sha256'
  ) -Code "$Code-catalogue-capture-shape"
  if ([int]$capture.schema -ne 1 -or [string]$capture.kind -cne [string]$Authority.record.catalogue_definition_capture_kind -or
      [string]$capture.status -cne 'completed' -or [string]$capture.compiler_profile -cne [string]$Authority.record.compiler_profile -or
      [string]$capture.source.commit -cne [string]$Candidate.source.commit -or [string]$capture.source.tree -cne [string]$Candidate.source.tree -or
      [string]$capture.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256 -or
      [string]$capture.candidate_manifest.sha256 -cne [string]$Candidate.candidate_manifest.sha256 -or
      [string]$capture.candidate_manifest.record_sha256 -cne [string]$Candidate.candidate_manifest.record_sha256 -or
      [string]$capture.record_sha256 -cne [string]$Descriptor.record_sha256) {
    throw "[$Code-catalogue-capture-binding]"
  }
  Assert-MIR430PerformancePropertyNames -Value $capture.profile -Expected @('id','target','definition','engine','loaded_selection') -Code "$Code-catalogue-capture-profile-shape"
  $expectedSelection = Get-MIR430ExpectedProfileLoadedSelection -ProfileDefinition $Expected.profile -CandidateTarget $CandidateTarget -Authority $Authority -Code $Code
  if ([string]$capture.profile.id -cne [string]$Profile.id -or [string]$capture.profile.target -cne [string]$Profile.target -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $capture.profile.definition) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $Expected.definition) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $capture.profile.engine) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $Expected.profile.engine) -or
      ((@($capture.profile.loaded_selection | ForEach-Object { [string]$_ } | Sort-Object) -join '|') -cne ($expectedSelection -join '|'))) {
    throw "[$Code-catalogue-capture-profile-binding]"
  }
  Assert-MIR430PerformancePropertyNames -Value $capture.settings -Expected @('kind') -Code "$Code-catalogue-capture-settings-shape"
  if ([string]$capture.settings.kind -cne [string]$Authority.record.default_settings_mode) { throw "[$Code-catalogue-capture-settings-binding]" }
  if ([string]$capture.capture_mode -cnotin @('upgrade-preservation-proof','matched-startup-capture')) { throw "[$Code-catalogue-capture-mode]" }
  Assert-MIR430PerformancePropertyNames -Value $capture.baseline -Expected @('source_version','distribution_version','profile_definition_sha256','engine_sha256','settings_kind','compiler_profile_marker','upstream_selection_sha256','raw_snapshot') -Code "$Code-catalogue-capture-baseline-shape"
  Assert-MIR430PerformancePropertyNames -Value $capture.candidate_catalogue -Expected @('compiler_profile_marker','settings_kind','upstream_selection_sha256','raw_snapshot') -Code "$Code-catalogue-capture-candidate-shape"
  $nativeDescriptorFields = if ([string]$capture.capture_mode -ceq 'matched-startup-capture') {
    @('path','sha256','source_sample_label','candidate_sample_label')
  } else { @('path','sha256') }
  Assert-MIR430PerformancePropertyNames -Value $capture.native_run -Expected $nativeDescriptorFields -Code "$Code-catalogue-capture-native-run-shape"
  $expectedUpstreamSelection = @(
    Get-MIR430ExpectedProfileLoadedSelection -ProfileDefinition $Expected.profile -CandidateTarget $CandidateTarget -Authority $Authority -Code $Code |
      Where-Object { $_ -notmatch '^more-infinite-research@' -and $_ -notmatch ('^' + [regex]::Escape([string]$Authority.record.allowed_observer.name) + '@') }
  )
  $expectedUpstreamSelectionSha = Get-MIR430PerformanceTextSha256 -Text ($expectedUpstreamSelection -join "`n")
  if ([string]$capture.baseline.source_version -cne '4.2.2' -or [string]$capture.baseline.distribution_version -cne '4.2.20002' -or
      [string]$capture.baseline.profile_definition_sha256 -cne [string]$Expected.definition.sha256 -or
      [string]$capture.baseline.engine_sha256 -cne [string]$Expected.profile.engine.sha256 -or
      [string]$capture.baseline.settings_kind -cne [string]$Authority.record.default_settings_mode -or
      [string]$capture.baseline.compiler_profile_marker -cne 'absent' -or
      [string]$capture.baseline.upstream_selection_sha256 -cne $expectedUpstreamSelectionSha -or
      [string]$capture.candidate_catalogue.compiler_profile_marker -cne [string]$Authority.record.compiler_profile -or
      [string]$capture.candidate_catalogue.settings_kind -cne [string]$Authority.record.default_settings_mode -or
      [string]$capture.candidate_catalogue.upstream_selection_sha256 -cne $expectedUpstreamSelectionSha) {
    throw "[$Code-catalogue-definition-binding]"
  }
  $baselineActive = @($expectedSelection | ForEach-Object { if ($_ -match '^more-infinite-research@') { 'more-infinite-research@4.2.20002' } else { $_ } })
  $candidateActive = @($expectedSelection)
  $candidateStage = if ([string]$capture.capture_mode -ceq 'matched-startup-capture') {'candidate'} else {'upgrade'}
  $baselineRaw = Get-MIR430FullSnapshotProjection -ObservationPath $capturePath -Descriptor $capture.baseline.raw_snapshot -Stage source -ExpectedActiveSelection $baselineActive -ExpectedCompilerProfile 'absent' -Code "$Code-catalogue-capture-baseline" -CaptureMode ([string]$capture.capture_mode) -ExpectedPackageVersion '4.2.20002'
  $candidateRaw = Get-MIR430FullSnapshotProjection -ObservationPath $capturePath -Descriptor $capture.candidate_catalogue.raw_snapshot -Stage $candidateStage -ExpectedActiveSelection $candidateActive -ExpectedCompilerProfile ([string]$Authority.record.compiler_profile) -Code "$Code-catalogue-capture-candidate" -CaptureMode ([string]$capture.capture_mode) -ExpectedPackageVersion ([string]$CandidateTarget.distribution_version)
  $upgradeSnapshotMismatch = [string]$capture.capture_mode -ceq 'upgrade-preservation-proof' -and (
    [string]$baselineRaw.snapshot.from_version -cne '4.2.20002' -or [string]$baselineRaw.snapshot.to_version -cne [string]$CandidateTarget.distribution_version -or
    [string]$candidateRaw.snapshot.from_version -cne '4.2.20002' -or [string]$candidateRaw.snapshot.to_version -cne [string]$CandidateTarget.distribution_version)
  if ($upgradeSnapshotMismatch -or
      [string]$baselineRaw.technology_ids_sha256 -cne [string]$candidateRaw.technology_ids_sha256 -or
      [string]$baselineRaw.semantic_definitions_sha256 -cne [string]$candidateRaw.semantic_definitions_sha256 -or
      [string]$baselineRaw.settings_sha256 -cne [string]$candidateRaw.settings_sha256) { throw "[$Code-catalogue-definition-binding]" }
  if ([string]$capture.capture_mode -ceq 'matched-startup-capture') {
    $matched = Assert-MIR430MatchedStartupCaptureRun -ObservationPath $capturePath -Descriptor $capture.native_run -Expected $Expected -CandidateTarget $CandidateTarget -Authority $Authority -BaselineSelection $baselineActive -CandidateSelection $candidateActive -BaselineRawPath $baselineRaw.path -CandidateRawPath $candidateRaw.path -Code "$Code-catalogue-capture"
    return [pscustomobject][ordered]@{path=$capturePath;record=$capture;baseline=$baselineRaw;candidate=$candidateRaw;native_run=$matched.record}
  }
  $nativeRunPath = Resolve-MIR430PerformanceEvidenceFile -ObservationPath $capturePath -Descriptor $capture.native_run -Code "$Code-catalogue-capture-native-run"
  try { $nativeRun = Get-Content -Raw -LiteralPath $nativeRunPath | ConvertFrom-Json -Depth 100 -DateKind String } catch { throw "[$Code-catalogue-capture-native-run-json]" }
  foreach ($field in @('status','factorio_binary_version','factorio_binary_sha256','from','to','assertions','full_state_evaluator_snapshots','source_library_activation','library_activation')) { if ($nativeRun.PSObject.Properties.Name -notcontains $field) { throw "[$Code-catalogue-capture-native-run-shape]" } }
  $requiredAssertions = @('all-existing-technology-state-and-definitions-retained','all-exposed-earned-effects-retained','all-supported-research-queue-retained','full-state-oracle-executed-upgrade-and-two-reloads')
  $nativeRows = @($nativeRun.full_state_evaluator_snapshots)
  $sourceRow = @($nativeRows | Where-Object { [string]$_.stage -ceq 'source' -and [string]$_.sha256 -ceq [string]$baselineRaw.sha256 })
  $upgradeRow = @($nativeRows | Where-Object { [string]$_.stage -ceq 'upgrade' -and [string]$_.sha256 -ceq [string]$candidateRaw.sha256 })
  if ([string]$nativeRun.status -cne 'passed' -or [string]$nativeRun.factorio_binary_sha256 -cne [string]$Expected.profile.engine.sha256 -or
      [string]$nativeRun.factorio_binary_version -notmatch ('^' + [regex]::Escape([string]$Expected.profile.engine.version) + '(?:[.]|$)') -or
      [string]$nativeRun.from.version -cne '4.2.20002' -or [string]$nativeRun.from.sha256 -cne '14C2B23E0F4657F9F79585A982639463678D640C04916FEECC365D93B6894A65' -or
      [string]$nativeRun.to.version -cne [string]$CandidateTarget.distribution_version -or [string]$nativeRun.to.sha256 -cne [string]$CandidateTarget.archive.sha256 -or
      @($requiredAssertions | Where-Object { $_ -cnotin @($nativeRun.assertions | ForEach-Object { [string]$_ }) }).Count -ne 0 -or $sourceRow.Count -ne 1 -or $upgradeRow.Count -ne 1) {
    throw "[$Code-catalogue-capture-native-run-binding]"
  }
  $nativeSourceSelection = Get-MIR430PerformanceActivationSelection -Activation $nativeRun.source_library_activation -Code "$Code-catalogue-capture-source-activation"
  $nativeCandidateSelection = Get-MIR430PerformanceActivationSelection -Activation $nativeRun.library_activation -Code "$Code-catalogue-capture-candidate-activation"
  if (($nativeSourceSelection -join '|') -cne (@($baselineActive | Sort-Object) -join '|') -or
      ($nativeCandidateSelection -join '|') -cne (@($candidateActive | Sort-Object) -join '|')) {
    throw "[$Code-catalogue-capture-native-run-selection]"
  }
  return [pscustomobject][ordered]@{path=$capturePath;record=$capture;baseline=$baselineRaw;candidate=$candidateRaw;native_run=$nativeRun}
}

function Get-MIR430PerformanceCandidateTarget {
  param([Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$Code)

  $rows = if ($Candidate.PSObject.Properties.Name -contains 'target_rows') { @($Candidate.target_rows) } else { @($Candidate.targets) }
  $match = @($rows | Where-Object { [string]$_.target -ceq $Target })
  if ($match.Count -ne 1) { throw "[$Code-target] $Target" }
  $row = $match[0]
  $archive = if ($row.PSObject.Properties.Name -contains 'archive') { $row.archive } else {
    [pscustomobject][ordered]@{
      path=[string]$row.archive_path
      sha256=[string]$row.archive_sha256
      bytes=[int64](Get-Item -LiteralPath ([string]$row.archive_path)).Length
      content_sha256=[string]$row.content_sha256
      entry_count=[int]$row.entry_count
    }
  }
  Assert-MIR430PerformancePropertyNames -Value $archive -Expected @('path','sha256','bytes','content_sha256','entry_count') -Code "$Code-archive-shape"
  return [pscustomobject][ordered]@{
    target=$Target
    source_version=[string]$Candidate.source_version
    package_source_sha256=[string]$Candidate.source.package_source_sha256
    distribution_version=$(if ($row.PSObject.Properties.Name -contains 'identity') {[string]$row.identity.distribution_version} else {[string]$row.distribution_version})
    archive=[pscustomobject][ordered]@{sha256=[string]$archive.sha256;bytes=[int64]$archive.bytes;content_sha256=[string]$archive.content_sha256;entry_count=[int]$archive.entry_count}
  }
}

function Resolve-MIR430PerformanceInvocationArtifact {
  param([Parameter(Mandatory)][string]$InvocationPath,[Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Code)
  if ([string]::IsNullOrWhiteSpace($RelativePath)) { throw "[$Code-path]" }
  $root = [IO.Path]::GetFullPath((Split-Path -Parent $InvocationPath)).TrimEnd([char[]]@('/','\'))
  $candidate = if ([IO.Path]::IsPathRooted($RelativePath)) {[IO.Path]::GetFullPath($RelativePath)} else {[IO.Path]::GetFullPath((Join-Path $root $RelativePath))}
  $prefix = $root + [IO.Path]::DirectorySeparatorChar
  if (-not $candidate.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw "[$Code-path]" }
  return $candidate
}

function Get-MIR430ExpectedProfileLoadedSelection {
  param([Parameter(Mandatory)]$ProfileDefinition,[Parameter(Mandatory)]$CandidateTarget,[Parameter(Mandatory)]$Authority,[Parameter(Mandatory)][string]$Code)
  $declared = @($ProfileDefinition.mods)
  $pins = @($ProfileDefinition.builtin_pins) + @($ProfileDefinition.archive_pins)
  $declaredByName = @{}
  foreach ($row in $declared) {
    if (-not [bool]$row.enabled -or [string]::IsNullOrWhiteSpace([string]$row.name) -or [string]::IsNullOrWhiteSpace([string]$row.version) -or $declaredByName.ContainsKey([string]$row.name)) { throw "[$Code-profile-selection]" }
    $declaredByName[[string]$row.name] = [string]$row.version
  }
  $pinnedByName = @{}
  foreach ($pin in $pins) {
    if ([string]::IsNullOrWhiteSpace([string]$pin.name) -or [string]::IsNullOrWhiteSpace([string]$pin.version) -or $pinnedByName.ContainsKey([string]$pin.name)) { throw "[$Code-profile-pins]" }
    $pinnedByName[[string]$pin.name] = [string]$pin.version
  }
  if ($declaredByName.Count -ne $pinnedByName.Count) { throw "[$Code-profile-pins]" }
  foreach ($name in $pinnedByName.Keys) {
    if (-not $declaredByName.ContainsKey($name) -or [string]$declaredByName[$name] -cne [string]$pinnedByName[$name]) { throw "[$Code-profile-pins]" }
  }
  $selection = [Collections.Generic.List[string]]::new()
  foreach ($name in $declaredByName.Keys) { $selection.Add($name + '@' + $declaredByName[$name]) }
  $selection.Add('more-infinite-research@' + [string]$CandidateTarget.distribution_version)
  $selection.Add([string]$Authority.record.allowed_observer.name + '@' + [string]$Authority.record.allowed_observer.version)
  return @($selection | Sort-Object)
}

function Get-MIR430ExpectedProfileArchiveSelection {
  param([Parameter(Mandatory)]$ProfileDefinition,[Parameter(Mandatory)]$CandidateTarget,[Parameter(Mandatory)]$Authority,[Parameter(Mandatory)][string]$Code)
  $expected = [Collections.Generic.List[object]]::new()
  foreach ($pin in @($ProfileDefinition.builtin_pins)) {
    if ([string]::IsNullOrWhiteSpace([string]$pin.name) -or [string]::IsNullOrWhiteSpace([string]$pin.version) -or [string]$pin.info_sha256 -notmatch '^[A-F0-9]{64}$') { throw "[$Code-profile-pins]" }
    $expected.Add([pscustomobject][ordered]@{name=[string]$pin.name;version=[string]$pin.version;sha256=[string]$pin.info_sha256;builtin=$true;bytes=$null})
  }
  foreach ($pin in @($ProfileDefinition.archive_pins)) {
    if ([string]::IsNullOrWhiteSpace([string]$pin.name) -or [string]::IsNullOrWhiteSpace([string]$pin.version) -or [string]$pin.sha256 -notmatch '^[A-F0-9]{64}$') { throw "[$Code-profile-pins]" }
    $expected.Add([pscustomobject][ordered]@{name=[string]$pin.name;version=[string]$pin.version;sha256=[string]$pin.sha256;builtin=$false;bytes=[int64]$pin.bytes})
  }
  $expected.Add([pscustomobject][ordered]@{name='more-infinite-research';version=[string]$CandidateTarget.distribution_version;sha256=[string]$CandidateTarget.archive.sha256;builtin=$false;bytes=[int64]$CandidateTarget.archive.bytes})
  $expected.Add([pscustomobject][ordered]@{name=[string]$Authority.record.allowed_observer.name;version=[string]$Authority.record.allowed_observer.version;sha256=[string]$Authority.record.allowed_observer.archive_sha256;builtin=$false;bytes=$null})
  $keys = @($expected | ForEach-Object { $_.name + '@' + $_.version })
  if (@($keys | Sort-Object -Unique).Count -ne $keys.Count) { throw "[$Code-profile-pins]" }
  return @($expected | Sort-Object name,version)
}

function Get-MIR430PerformanceLogIdentity {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ObserverName,[Parameter(Mandatory)][string]$Code)
  $text = Get-Content -Raw -LiteralPath $Path
  $headers = @([regex]::Matches($text,'(?m)^\s*[0-9]+(?:[.]?[0-9]+)?\s+.*; Factorio (?<version>[0-9]+[.][0-9]+[.][0-9]+) '))
  if ($headers.Count -ne 1) { throw "[$Code-engine-log]" }
  $loaded = @([regex]::Matches($text,'(?m)Loading mod (?:settings )?(?<name>[^\r\n]+?) (?<version>[0-9]+[.][0-9]+[.][0-9]+) \(') | ForEach-Object {
    [string]$_.Groups['name'].Value + '@' + ([version]$_.Groups['version'].Value).ToString()
  } | Where-Object { $_ -notlike 'core@*' } | Sort-Object -Unique)
  if ($loaded.Count -eq 0) { throw "[$Code-loaded-log]" }
  $marker = '(?m)^\s*[0-9]+(?:[.][0-9]+)? Script @__' + [regex]::Escape($ObserverName) + '__/data-final-fixes[.]lua:[0-9]+: \[MIR_ACTIVE_MODS\] (?<mods>[^\r\n]+)\r?$'
  $reported = @([regex]::Matches($text,$marker))
  if ($reported.Count -ne 1) { throw "[$Code-active-mods]" }
  $active = [Collections.Generic.List[string]]::new()
  foreach ($row in @($reported[0].Groups['mods'].Value.Split('|'))) {
    if ($row -cnotmatch '^(?<name>.+)@(?<version>[0-9]+[.][0-9]+[.][0-9]+)$') { throw "[$Code-active-mods]" }
    $active.Add([string]$Matches['name'] + '@' + ([version]$Matches['version']).ToString())
  }
  $activeSelection = @($active | Sort-Object)
  if ($activeSelection.Count -eq 0 -or @($activeSelection | Sort-Object -Unique).Count -ne $activeSelection.Count) { throw "[$Code-active-mods]" }
  return [pscustomobject][ordered]@{engine_version=([version]$headers[0].Groups['version'].Value).ToString();loaded_selection=$loaded;active_selection=$activeSelection}
}

function Get-MIR430PerformanceInvocationSample {
  param(
    [Parameter(Mandatory)][string]$ObservationPath,[Parameter(Mandatory)]$Invocation,[Parameter(Mandatory)]$ProfileDefinition,
    [Parameter(Mandatory)]$CandidateTarget,[Parameter(Mandatory)]$Authority,[Parameter(Mandatory)][string]$ObservedLogPath,
    [Parameter(Mandatory)][string]$ObservedLedgerPath,[Parameter(Mandatory)][string]$Code
  )
  Assert-MIR430PerformancePropertyNames -Value $Invocation -Expected @('path','sha256','sample_label','sample_ordinal') -Code "$Code-invocation-shape"
  if ([string]::IsNullOrWhiteSpace([string]$Invocation.sample_label) -or [int]$Invocation.sample_ordinal -lt 1) { throw "[$Code-invocation-binding]" }
  $path = Resolve-MIR430PerformanceEvidenceFile -ObservationPath $ObservationPath -Descriptor ([pscustomobject][ordered]@{path=[string]$Invocation.path;sha256=[string]$Invocation.sha256}) -Code "$Code-invocation"
  $item = Get-Item -LiteralPath $path
  if ($item.Length -le 0 -or $item.Length -gt 64MB) { throw "[$Code-invocation-size]" }
  try { $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100 -DateKind String } catch { throw "[$Code-invocation-json]" }
  foreach ($field in @('schema','kind','status','mode','target','factorio','inputs','endpoint_class','resource_context','samples','library','library_controls_restored')) {
    if ($record.PSObject.Properties.Name -notcontains $field) { throw "[$Code-invocation-shape]" }
  }
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIRDirectLibraryStartupMeasurementV1' -or [string]$record.status -cne 'completed' -or
      [string]$record.mode -cnotin @('matched-three-input','candidate-only-stress-diagnostic') -or
      [string]$record.target -cne 'f200' -or [string]$record.endpoint_class -cne 'headless-create-diagnostic' -or -not [bool]$record.library_controls_restored) { throw "[$Code-invocation-state]" }
  if ($record.factorio.PSObject.Properties.Name -notcontains 'sha256' -or $record.factorio.PSObject.Properties.Name -notcontains 'base_version' -or
      [string]$record.factorio.sha256 -cne [string]$ProfileDefinition.engine.sha256 -or [string]$record.factorio.base_version -cne [string]$ProfileDefinition.engine.version) { throw "[$Code-invocation-engine]" }
  if ($record.inputs.PSObject.Properties.Name -notcontains 'candidate' -or $null -eq $record.inputs.candidate -or
      [string]$record.inputs.candidate.source_version -cne [string]$CandidateTarget.source_version -or
      [string]$record.inputs.candidate.archive.sha256 -cne [string]$CandidateTarget.archive.sha256 -or
      [string]$record.inputs.candidate.materialization.source_version -cne [string]$CandidateTarget.source_version -or
      [string]$record.inputs.candidate.materialization.archive_sha256 -cne [string]$CandidateTarget.archive.sha256 -or
      [string]$record.inputs.candidate.materialization.package_source_sha256 -cne [string]$CandidateTarget.package_source_sha256) { throw "[$Code-invocation-candidate]" }
  $matches = @($record.samples | Where-Object { [string]$_.label -ceq [string]$Invocation.sample_label -and [int]$_.sample -eq [int]$Invocation.sample_ordinal })
  if ($matches.Count -ne 1) { throw "[$Code-invocation-sample]" }
  $sample = $matches[0]
  foreach ($field in @('label','sample','run_relative_path','exit_code','endpoint_class','ready_save','map_generation','loaded_selection','active_mods_observer','resource_ledger','log','engine_current_log','execution_controls')) {
    if ($sample.PSObject.Properties.Name -notcontains $field) { throw "[$Code-invocation-sample]" }
  }
  if ([int]$sample.exit_code -ne 0 -or [string]$sample.endpoint_class -cne 'headless-create-diagnostic') { throw "[$Code-invocation-sample]" }
  $run = [string]$sample.run_relative_path
  if ([string]::IsNullOrWhiteSpace($run)) { throw "[$Code-invocation-sample]" }
  $relativeRun = $run.TrimEnd([char[]]@('/','\'))
  Assert-MIR430PerformancePropertyNames -Value $sample.execution_controls -Expected @('engine_sha256','arguments_sha256','config','selection','mod_settings','library_directory') -Code "$Code-invocation-controls-shape"
  if ([string]$sample.execution_controls.engine_sha256 -cne [string]$record.factorio.sha256 -or
      [string]$sample.execution_controls.engine_sha256 -cne [string]$ProfileDefinition.engine.sha256 -or
      [string]$sample.execution_controls.arguments_sha256 -notmatch '^[A-F0-9]{64}$' -or
      [string]$sample.execution_controls.library_directory -cne [string]$record.library) { throw "[$Code-invocation-controls]" }
  Assert-MIR430PerformancePropertyNames -Value $sample.execution_controls.config -Expected @('path','sha256') -Code "$Code-invocation-controls-shape"
  Assert-MIR430PerformancePropertyNames -Value $sample.execution_controls.selection -Expected @('path','sha256') -Code "$Code-invocation-controls-shape"
  Assert-MIR430PerformancePropertyNames -Value $sample.execution_controls.mod_settings -Expected @('kind','present') -Code "$Code-invocation-controls-shape"
  if ([string]$sample.execution_controls.mod_settings.kind -cne 'canonical-absent-default' -or [bool]$sample.execution_controls.mod_settings.present) { throw "[$Code-invocation-settings]" }
  $sampleLog = Resolve-MIR430PerformanceInvocationArtifact -InvocationPath $path -RelativePath ($relativeRun + '/' + [string]$sample.log) -Code "$Code-invocation-log"
  $sampleLedger = Resolve-MIR430PerformanceInvocationArtifact -InvocationPath $path -RelativePath ([string]$sample.resource_ledger) -Code "$Code-invocation-ledger"
  if ([string](Get-MIR4Sha256File -Path $sampleLog) -cne [string](Get-MIR4Sha256File -Path $ObservedLogPath) -or
      [string](Get-MIR4Sha256File -Path $sampleLedger) -cne [string](Get-MIR4Sha256File -Path $ObservedLedgerPath)) { throw "[$Code-invocation-evidence]" }
  $processes = @($record.resource_context.processes | Where-Object {
    [string]$_.status -ceq 'passed' -and $null -ne $_.result -and [bool]$_.result.passed -and [int]$_.result.exit_code -eq 0 -and
    (Resolve-MIR430PerformanceInvocationArtifact -InvocationPath $path -RelativePath ([string]$_.ledger) -Code "$Code-invocation-ledger") -ceq $sampleLedger
  })
  if ($processes.Count -ne 1) { throw "[$Code-invocation-ledger]" }
  $expectedSelection = Get-MIR430ExpectedProfileLoadedSelection -ProfileDefinition $ProfileDefinition -CandidateTarget $CandidateTarget -Authority $Authority -Code $Code
  $reportedSelection = @($sample.loaded_selection | ForEach-Object { [string]$_ } | Sort-Object)
  if (($reportedSelection -join '|') -cne ($expectedSelection -join '|')) { throw "[$Code-invocation-selection]" }
  if ([string]$sample.active_mods_observer.name -cne [string]$Authority.record.allowed_observer.name -or
      [string]$sample.active_mods_observer.version -cne [string]$Authority.record.allowed_observer.version -or
      [string]$sample.active_mods_observer.sha256 -cne [string]$Authority.record.allowed_observer.archive_sha256) { throw "[$Code-invocation-observer]" }
  if ($sample.PSObject.Properties.Name -notcontains 'loaded_archives') { throw "[$Code-invocation-archives]" }
  $expectedArchives = Get-MIR430ExpectedProfileArchiveSelection -ProfileDefinition $ProfileDefinition -CandidateTarget $CandidateTarget -Authority $Authority -Code $Code
  $actualArchives = @($sample.loaded_archives)
  if ($actualArchives.Count -ne $expectedArchives.Count) { throw "[$Code-invocation-archives]" }
  $actualArchiveByKey = @{}
  foreach ($archive in $actualArchives) {
    Assert-MIR430PerformancePropertyNames -Value $archive -Expected @('name','version','sha256','builtin','bytes') -Code "$Code-invocation-archive-shape"
    $key = [string]$archive.name + '@' + [string]$archive.version
    if ([string]::IsNullOrWhiteSpace([string]$archive.name) -or [string]::IsNullOrWhiteSpace([string]$archive.version) -or [string]$archive.sha256 -notmatch '^[A-F0-9]{64}$' -or
        $archive.builtin -isnot [bool] -or [int64]$archive.bytes -le 0 -or $actualArchiveByKey.ContainsKey($key)) { throw "[$Code-invocation-archives]" }
    $actualArchiveByKey[$key] = $archive
  }
  foreach ($expectedArchive in $expectedArchives) {
    $key = [string]$expectedArchive.name + '@' + [string]$expectedArchive.version
    if (-not $actualArchiveByKey.ContainsKey($key)) { throw "[$Code-invocation-archives]" }
    $actualArchive = $actualArchiveByKey[$key]
    if ([string]$actualArchive.sha256 -cne [string]$expectedArchive.sha256 -or [bool]$actualArchive.builtin -ne [bool]$expectedArchive.builtin -or
        ($null -ne $expectedArchive.bytes -and [int64]$actualArchive.bytes -ne [int64]$expectedArchive.bytes)) { throw "[$Code-invocation-archives]" }
  }
  $selectionPath = Resolve-MIR430PerformanceInvocationArtifact -InvocationPath $path -RelativePath ($relativeRun + '/selection.json') -Code "$Code-invocation-selection"
  $configPath = Resolve-MIR430PerformanceInvocationArtifact -InvocationPath $path -RelativePath ($relativeRun + '/config.ini') -Code "$Code-invocation-config"
  $controlConfig = Resolve-MIR430PerformanceInvocationArtifact -InvocationPath $path -RelativePath ($relativeRun + '/' + [string]$sample.execution_controls.config.path) -Code "$Code-invocation-controls"
  $controlSelection = Resolve-MIR430PerformanceInvocationArtifact -InvocationPath $path -RelativePath ($relativeRun + '/' + [string]$sample.execution_controls.selection.path) -Code "$Code-invocation-controls"
  if ($controlConfig -cne $configPath -or $controlSelection -cne $selectionPath -or
      [string](Get-MIR4Sha256File -Path $controlConfig) -cne [string]$sample.execution_controls.config.sha256 -or
      [string](Get-MIR4Sha256File -Path $controlSelection) -cne [string]$sample.execution_controls.selection.sha256) { throw "[$Code-invocation-controls]" }
  Assert-MIR430PerformancePropertyNames -Value $sample.map_generation -Expected @('seed','path','sha256') -Code "$Code-invocation-controls-shape"
  if ([int64]$sample.map_generation.seed -lt 0 -or [int64]$sample.map_generation.seed -gt [uint32]::MaxValue -or [string]$sample.map_generation.sha256 -notmatch '^[A-F0-9]{64}$') { throw "[$Code-invocation-controls]" }
  $mapGeneration = Resolve-MIR430PerformanceInvocationArtifact -InvocationPath $path -RelativePath ([string]$sample.map_generation.path) -Code "$Code-invocation-controls"
  $readySave = Resolve-MIR430PerformanceInvocationArtifact -InvocationPath $path -RelativePath ($relativeRun + '/' + [string]$sample.ready_save) -Code "$Code-invocation-controls"
  $engineCurrentLog = Resolve-MIR430PerformanceInvocationArtifact -InvocationPath $path -RelativePath ([string]$sample.engine_current_log) -Code "$Code-invocation-controls"
  if ([string](Get-MIR4Sha256File -Path $mapGeneration) -cne [string]$sample.map_generation.sha256) { throw "[$Code-invocation-controls]" }
  $configText = Get-Content -Raw -LiteralPath $controlConfig
  $writeData = [regex]::Match($configText,'(?m)^write-data=(?<path>[^\r\n]+)\s*$')
  $readData = [regex]::Match($configText,'(?m)^read-data=(?<path>[^\r\n]+)\s*$')
  if (-not $writeData.Success -or -not $readData.Success -or [string]::IsNullOrWhiteSpace($writeData.Groups['path'].Value) -or [string]::IsNullOrWhiteSpace($readData.Groups['path'].Value) -or
      [IO.Path]::GetFullPath((Join-Path $writeData.Groups['path'].Value 'factorio-current.log')) -cne $engineCurrentLog) { throw "[$Code-invocation-controls]" }
  $launchArguments = @('--config',$controlConfig,'--mod-directory',[string]$sample.execution_controls.library_directory,'--no-log-rotation','--disable-audio','--map-gen-settings',$mapGeneration,'--create',$readySave)
  $launchArgumentSha = Get-MIR430PerformanceTextSha256 -Text (ConvertTo-Json -InputObject $launchArguments -Compress)
  if ($launchArgumentSha -cne [string]$sample.execution_controls.arguments_sha256) { throw "[$Code-invocation-controls]" }
  try { $selection = Get-Content -Raw -LiteralPath $selectionPath | ConvertFrom-Json -Depth 20 -DateKind String } catch { throw "[$Code-invocation-selection]" }
  $selectionRows = @($selection.mods | ForEach-Object { if (-not [bool]$_.enabled) { throw "[$Code-invocation-selection]" }; [string]$_.name + '@' + [string]$_.version } | Sort-Object)
  if (($selectionRows -join '|') -cne ($expectedSelection -join '|')) { throw "[$Code-invocation-selection]" }
  $config = Get-Content -Raw -LiteralPath $configPath
  if ($config -notmatch '(?m)^enable-new-mods=false\s*$' -or $config -notmatch '(?m)^read-data=' -or $config -notmatch '(?m)^write-data=') { throw "[$Code-invocation-config]" }
  $logIdentity = Get-MIR430PerformanceLogIdentity -Path $sampleLog -ObserverName ([string]$Authority.record.allowed_observer.name) -Code "$Code-invocation"
  if ([string]$logIdentity.engine_version -cne [string]$ProfileDefinition.engine.version -or
      ($logIdentity.active_selection -join '|') -cne ($expectedSelection -join '|') -or
      @($logIdentity.loaded_selection | Where-Object { $_ -cnotin $expectedSelection }).Count -ne 0) { throw "[$Code-invocation-log-binding]" }
  return [pscustomobject][ordered]@{path=$path;sample=$sample}
}
function Assert-MIR430FullStartupStressObservation {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Candidate,
    [Parameter(Mandatory)][string]$Code
  )

  $authority = Get-MIR430EmergencyPerformanceAuthority -RepoRoot $RepoRoot
  if ([string]$Candidate.source_version -cne [string]$authority.record.source_version) { throw "[$Code-source-version]" }
  $record = Read-MIR42QualificationBootstrapRecord -Path $Path -Code $Code
  $schema = Join-Path $RepoRoot 'spec/schemas/mir430-classic-startup-stress-observation-v1.schema.json'
  if (-not (Test-Path -LiteralPath $schema -PathType Leaf) -or -not ((Get-Content -Raw -LiteralPath $Path) | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue)) {
    throw "[$Code-schema]"
  }
  Assert-MIR430PerformancePropertyNames -Value $record -Expected @(
    'schema','kind','status','source','candidate_manifest','authority','compiler_profile','profiles','record_sha256'
  ) -Code "$Code-shape"
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR430FullStartupStressObservationV1' -or [string]$record.status -cne 'completed' -or
      [string]$record.compiler_profile -cne [string]$authority.record.compiler_profile -or
      [string]$record.source.commit -cne [string]$Candidate.source.commit -or [string]$record.source.tree -cne [string]$Candidate.source.tree -or
      [string]$record.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256 -or
      [string]$record.candidate_manifest.sha256 -cne [string]$Candidate.candidate_manifest.sha256 -or
      [string]$record.candidate_manifest.record_sha256 -cne [string]$Candidate.candidate_manifest.record_sha256) {
    throw "[$Code-binding]"
  }
  Assert-MIR430PerformancePropertyNames -Value $record.authority -Expected @('path','sha256','record_sha256') -Code "$Code-authority-shape"
  if ([string]$record.authority.path -cne $script:MIR430EmergencyPerformanceAuthorityPath -or [string]$record.authority.sha256 -cne [string]$authority.sha256 -or
      [string]$record.authority.record_sha256 -cne [string]$authority.record.record_sha256) {
    throw "[$Code-authority-binding]"
  }
  $profiles = @($record.profiles)
  if ($profiles.Count -ne $authority.profiles.Count -or (@($profiles | ForEach-Object { [string]$_.id }) -join '|') -cne (@($authority.profiles | ForEach-Object { [string]$_.id }) -join '|')) {
    throw "[$Code-profiles]"
  }
  foreach ($expected in $authority.profiles) {
    $profile = @($profiles | Where-Object { [string]$_.id -ceq [string]$expected.id })[0]
    Assert-MIR430PerformancePropertyNames -Value $profile -Expected @('id','target','definition','settings','engine','candidate','observer','full_catalogue_capture','samples') -Code "$Code-profile-shape"
    if ([string]$profile.target -cne [string]$expected.target -or
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $profile.definition) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $expected.definition) -or
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $profile.engine) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $expected.profile.engine) -or
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $profile.observer) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $authority.record.allowed_observer)) {
      throw "[$Code-profile-binding] $([string]$expected.id)"
    }
    $rawSettingsClaim = $false
    if ([string]$profile.settings.kind -ceq 'raw-sha256') {
      Assert-MIR430PerformancePropertyNames -Value $profile.settings -Expected @('kind','path','sha256') -Code "$Code-settings-shape"
      $settingsPath = Resolve-MIR430PerformanceEvidenceFile -ObservationPath $Path -Descriptor ([pscustomobject][ordered]@{path=[string]$profile.settings.path;sha256=[string]$profile.settings.sha256}) -Code "$Code-settings"
      if ([string]::IsNullOrWhiteSpace($settingsPath)) { throw "[$Code-settings-binding]" }
      $rawSettingsClaim = $true
    } elseif ([string]$profile.settings.kind -ceq 'canonical-absent-default') {
      Assert-MIR430PerformancePropertyNames -Value $profile.settings -Expected @('kind') -Code "$Code-settings-shape"
    } else {
      throw "[$Code-settings-kind]"
    }
    $candidateTarget = Get-MIR430PerformanceCandidateTarget -Candidate $Candidate -Target ([string]$expected.target) -Code $Code
    Assert-MIR430PerformancePropertyNames -Value $profile.candidate -Expected @('target','source_version','distribution_version','archive') -Code "$Code-candidate-shape"
    Assert-MIR430PerformancePropertyNames -Value $profile.candidate.archive -Expected @('sha256','bytes','content_sha256','entry_count') -Code "$Code-candidate-archive-shape"
    $candidateClaim = [pscustomobject][ordered]@{target=[string]$candidateTarget.target;source_version=[string]$candidateTarget.source_version;distribution_version=[string]$candidateTarget.distribution_version;archive=$candidateTarget.archive}
    if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $profile.candidate) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $candidateClaim)) {
      throw "[$Code-candidate-binding] $([string]$expected.id)"
    }
    $catalogueCapture = Assert-MIR430FullCatalogueDefinitionCapture -ObservationPath $Path -Descriptor $profile.full_catalogue_capture -Profile $profile -Expected $expected -Candidate $Candidate -CandidateTarget $candidateTarget -Authority $authority -Code "$Code-$([string]$expected.id)"
    $samples = @($profile.samples)
    if ($samples.Count -lt [int]$authority.record.minimum_samples_per_profile -or @($samples | ForEach-Object { [string]$_.label } | Sort-Object -Unique).Count -ne $samples.Count) {
      throw "[$Code-samples] $([string]$expected.id)"
    }
    foreach ($sample in $samples) {
      Assert-MIR430PerformancePropertyNames -Value $sample -Expected @('label','status','endpoint_class','exit_code','log','resource_ledger','stages','total_seconds','invocation') -Code "$Code-sample-shape"
      if ([string]::IsNullOrWhiteSpace([string]$sample.label) -or [string]$sample.status -cne 'completed' -or [string]$sample.endpoint_class -cne 'headless-create-diagnostic' -or [int]$sample.exit_code -ne 0) {
        throw "[$Code-sample-state] $([string]$expected.id)"
      }
      $logPath = Resolve-MIR430PerformanceEvidenceFile -ObservationPath $Path -Descriptor $sample.log -Code "$Code-log"
      $ledgerPath = Resolve-MIR430PerformanceEvidenceFile -ObservationPath $Path -Descriptor $sample.resource_ledger -Code "$Code-resource-ledger"
      Get-MIR430PerformanceLedgerCompletion -Path $ledgerPath
      $null = Get-MIR430PerformanceInvocationSample -ObservationPath $Path -Invocation $sample.invocation -ProfileDefinition $expected.profile -CandidateTarget $candidateTarget -Authority $authority -ObservedLogPath $logPath -ObservedLedgerPath $ledgerPath -Code "$Code-$([string]$expected.id)"
      # DirectLibraryStartupMeasurement's headless path captures only the
      # activation Defaults lease. A caller-supplied settings-file hash is not
      # evidence that this invocation used that file.
      if ($rawSettingsClaim) { throw "[$Code-settings-binding] $([string]$expected.id)" }
      $parsedResult = Get-MIR430PerformanceParsedStages -Path $logPath -Stages @($authority.record.required_stages)
      if (@($parsedResult.technology_names).Count -ne @($catalogueCapture.candidate.technology_ids).Count -or
          [string]$parsedResult.technology_ids_sha256 -cne [string]$catalogueCapture.candidate.technology_ids_sha256) {
        throw "[$Code-catalogue-capture-log-binding] $([string]$expected.id)"
      }
      $parsed = @($parsedResult.stages)
      $reported = @($sample.stages)
      if ($reported.Count -ne $parsed.Count) { throw "[$Code-stage-count] $([string]$expected.id)" }
      $total = 0.0
      for ($index = 0; $index -lt $parsed.Count; $index++) {
        Assert-MIR430PerformancePropertyNames -Value $reported[$index] -Expected @('stage','begin_seconds','end_seconds','elapsed_seconds') -Code "$Code-stage-shape"
        foreach ($field in @('begin_seconds','end_seconds','elapsed_seconds')) {
          if (-not ($reported[$index].$field -is [ValueType]) -or [double]::IsNaN([double]$reported[$index].$field) -or [double]::IsInfinity([double]$reported[$index].$field)) { throw "[$Code-stage-number]" }
        }
        if ([string]$reported[$index].stage -cne [string]$parsed[$index].stage -or
            [double]$reported[$index].begin_seconds -ne [double]$parsed[$index].begin_seconds -or
            [double]$reported[$index].end_seconds -ne [double]$parsed[$index].end_seconds -or
            [double]$reported[$index].elapsed_seconds -ne [double]$parsed[$index].elapsed_seconds) {
          throw "[$Code-stage-claim] $([string]$expected.id)"
        }
        $total += [double]$parsed[$index].elapsed_seconds
      }
      if (-not ($sample.total_seconds -is [ValueType]) -or [double]::IsNaN([double]$sample.total_seconds) -or [double]::IsInfinity([double]$sample.total_seconds) -or
          [double]$sample.total_seconds -ne $total) {
        throw "[$Code-total-claim] $([string]$expected.id)"
      }
      if ($total -gt [double]$authority.record.max_mir_startup_seconds) { throw "[$Code-threshold] $([string]$expected.id)" }
    }
  }
  return [pscustomobject][ordered]@{path=(Resolve-Path -LiteralPath $Path).Path;sha256=(Get-MIR4Sha256File -Path $Path);record=$record;authority=$authority}
}

# Retain the former exported name for callers that have not yet been migrated.
# It validates the Full/default record above; Classic observations cannot pass it.
function Assert-MIR430ClassicStartupStressObservation {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Candidate,
    [Parameter(Mandatory)][string]$Code
  )
  return Assert-MIR430FullStartupStressObservation -RepoRoot $RepoRoot -Path $Path -Candidate $Candidate -Code $Code
}

function Resolve-MIR42CriterionEvidenceOutputPath {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $build = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
  $output = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repo $Path)) }
  try {
    $null = Assert-MIR4DescendantPath -Root $build -Path $output
    $null = Assert-MIR4NoReparseAncestors -Root $repo -Path $output
  } catch { throw '[mir42-criterion-evidence-output-containment]' }
  if (Test-Path -LiteralPath $output) { throw '[mir42-criterion-evidence-output-existing]' }
  $parent = Split-Path -Parent $output
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  return $output
}

function Get-MIR42CriterionObservationContract {
  param([Parameter(Mandatory)][string]$Criterion,[switch]$PublishedMaintenance,
    [ValidateSet('4.2.1','4.2.2','4.2.3','4.3.0','4.3.1','4.4.0','4.4.2','4.5.0','4.5.2')][string]$SourceVersion='4.2.1')
  $emergency430 = $SourceVersion -ceq '4.3.0'
  $normal431 = $SourceVersion -cin @('4.3.1','4.4.0','4.4.2','4.5.0','4.5.2')
  if ($PublishedMaintenance -and -not ($emergency430 -or $normal431) -and $Criterion -cnotin @('fresh-exact-loads','target-omissions')) {
    throw '[mir42-maintenance-criterion-input-scope]'
  }
  if ($Criterion -ceq 'fresh-exact-loads') {
    if ($PublishedMaintenance) {
      return [pscustomobject]@{kind='MIR42NineTargetMaintenanceRealEngineEvidenceBinderV1';status="MIR-$SourceVersion-NINE-TARGET-MAINTENANCE-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED"}
    }
    return [pscustomobject]@{kind='MIR42NineTargetRealEngineEvidenceBinderV1';status='MIR-4.2-NINE-TARGET-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED'}
  }
  if ($Criterion -ceq 'target-omissions') {
    if ($PublishedMaintenance) {
      return [pscustomobject]@{kind='MIR42NineTargetMaintenanceEvidenceReconciliationV1';status="MIR-$SourceVersion-NINE-TARGET-MAINTENANCE-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED"}
    }
    return [pscustomobject]@{kind='MIR42NineTargetEvidenceReconciliationV1';status='MIR-4.2-NINE-TARGET-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED'}
  }
  return $null
}

function Assert-MIR42MaintenanceCriterionObservation {
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$Criterion,[Parameter(Mandatory)]$PublishedInputs)
  $null = Get-MIR42CriterionObservationContract -Criterion $Criterion -PublishedMaintenance
  $expectedTargets = @($PublishedInputs.targets | ForEach-Object { [string]$_.target })
  $observedTargets = @($Record.targets | ForEach-Object { [string]$_.target })
  if ($expectedTargets.Count -ne 9 -or ($expectedTargets -join '|') -cne ($script:MIR42QualificationNineTargets -join '|') -or
      ($observedTargets -join '|') -cne ($expectedTargets -join '|') -or
      $Record.PSObject.Properties.Name -notcontains 'published_maintenance_predecessor' -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $Record.published_maintenance_predecessor) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $PublishedInputs)) {
    throw '[mir42-maintenance-criterion-custody-binding]'
  }
  for ($i = 0; $i -lt $expectedTargets.Count; $i++) {
    $row = @($Record.targets)[$i]
    $input = @($PublishedInputs.targets)[$i]
    if ($Criterion -ceq 'fresh-exact-loads') {
      $execution = $row.engine_execution
      if ($execution.PSObject.Properties.Name -notcontains 'published_maintenance_predecessor' -or
          (ConvertTo-MIR4BootstrapCanonicalJson -Value $execution.published_maintenance_predecessor) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $input) -or
          -not ([string]$execution.predecessor.path).Equals([string]$input.path,[StringComparison]::OrdinalIgnoreCase) -or
          [string]$execution.predecessor.version -cne [string]$input.version -or [string]$execution.predecessor.sha256 -cne [string]$input.sha256) {
        throw "[mir42-maintenance-criterion-predecessor-binding] $([string]$input.target)"
      }
    } else {
      if ($row.PSObject.Properties.Name -notcontains 'published_maintenance_predecessor' -or
          (ConvertTo-MIR4BootstrapCanonicalJson -Value $row.published_maintenance_predecessor) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $input)) {
        throw "[mir42-maintenance-criterion-row-custody-binding] $([string]$input.target)"
      }
      if ([string]$row.predecessor.version -cne [string]$input.version -or
          [string]$row.predecessor.archive.path -cne [IO.Path]::GetFileName([string]$input.path) -or
          [string]$row.predecessor.archive.sha256 -cne [string]$input.sha256 -or
          [int64]$row.predecessor.archive.bytes -ne [int64]$input.bytes -or
          [string]$row.predecessor.archive.content_sha256 -cne [string]$input.content_sha256 -or
          [int]$row.predecessor.archive.entry_count -ne [int]$input.entry_count) {
        throw "[mir42-maintenance-criterion-predecessor-binding] $([string]$input.target)"
      }
    }
  }
}

function Assert-MIR431NormalPerformanceTelemetryObservation {
  param(
    [Parameter(Mandatory)]$Record,
    [Parameter(Mandatory)]$Candidate,
    [Parameter(Mandatory)]$IndividualEngineCandidate,
    [Parameter(Mandatory)]$PublishedMaintenanceInputs,
    [Parameter(Mandatory)][string]$Code
  )

  # 4.3.1 returns to the ordinary nine-target performance criterion. Its
  # observation remains bound to the authenticated individual engine run, so
  # a self-reported result cannot replace archive, upgrade, reload, or
  # resource-ledger evidence.
  Assert-MIR430PerformancePropertyNames -Value $Record -Expected @(
    'schema','kind','status','criterion','telemetry_scope','compiler_profile',
    'source','candidate_manifest','individual_engine_run','record_sha256'
  ) -Code "$Code-shape"
  if ([int]$Record.schema -ne 1 -or
      [string]$Record.kind -cne 'MIR42NineTargetCriterionObservationV1' -or
      [string]$Record.status -cne 'passed' -or
      [string]$Record.criterion -cne 'performance-telemetry' -or
      [string]$Record.telemetry_scope -cne 'bounded-candidate-load-and-upgrade-resource-observation' -or
      [string]$Record.compiler_profile -cne 'full' -or
      [string]$Record.source.commit -cne [string]$Candidate.source.commit -or
      [string]$Record.source.tree -cne [string]$Candidate.source.tree -or
      [string]$Record.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256 -or
      [string]$Record.candidate_manifest.sha256 -cne [string]$Candidate.candidate_manifest.sha256 -or
      [string]$Record.candidate_manifest.record_sha256 -cne [string]$Candidate.candidate_manifest.record_sha256) {
    throw "[$Code-binding]"
  }
  Assert-MIR430PerformancePropertyNames -Value $Record.individual_engine_run -Expected @('path','sha256','record_sha256') -Code "$Code-engine-run-shape"

  # Technical Seal normally imports this module. For standalone criterion
  # production, load its existing authenticated run reader only after this
  # module has completed loading, avoiding a circular dot-source.
  if (-not (Get-Command Get-MIR42BoundEngineRun -ErrorAction SilentlyContinue)) {
    . (Join-Path $mir42QualificationRoot 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
  }
  $bound = Get-MIR42BoundEngineRun -Reference $Record.individual_engine_run -Candidate $IndividualEngineCandidate -PublishedMaintenanceInputs $PublishedMaintenanceInputs
  $expectedTargets = @($script:MIR42QualificationNineTargets)
  $actualTargets = @($bound.record.targets | ForEach-Object { [string]$_.target })
  if ([string]$bound.input_kind -cne 'individual-upgrade-receipts-and-fresh-loads' -or
      [string]$bound.sha256 -cne [string]$Record.individual_engine_run.sha256 -or
      [string]$bound.record.record_sha256 -cne [string]$Record.individual_engine_run.record_sha256 -or
      $actualTargets.Count -ne $expectedTargets.Count -or ($actualTargets -join '|') -cne ($expectedTargets -join '|')) {
    throw "[$Code-engine-run-binding]"
  }
  return $bound
}

function New-MIR431NormalPerformanceEngineCandidate {
  param(
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)]$Candidate
  )

  if ($Candidate.PSObject.Properties.Name -notcontains 'target_rows' -or @($Candidate.target_rows).Count -ne $script:MIR42QualificationNineTargets.Count) {
    throw '[mir431-normal-performance-candidate-shape]'
  }
  $root = Split-Path -Parent (Resolve-Path -LiteralPath $CandidateManifestPath).Path
  $targets = @(
    foreach ($row in @($Candidate.target_rows)) {
      $archivePath = Resolve-MIR42QualificationChildPath -Root $root -RelativePath ([string]$row.archive.path) -Code 'mir431-normal-performance-candidate-archive'
      [pscustomobject][ordered]@{
        target = [string]$row.target
        distribution_version = [string]$row.identity.distribution_version
        archive_sha256 = [string]$row.archive.sha256
        content_sha256 = [string]$row.archive.content_sha256
        entry_count = [int]$row.archive.entry_count
        archive_path = $archivePath
      }
    }
  )
  return [pscustomobject][ordered]@{
    identity = [pscustomobject][ordered]@{
      sha256 = [string]$Candidate.candidate_manifest.sha256
      record = [pscustomobject][ordered]@{record_sha256=[string]$Candidate.candidate_manifest.record_sha256}
    }
    source = $Candidate.source
    scope = 'nine-target'
    targets = $targets
  }
}

function Get-MIR42CriterionEvidenceObservation {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Criterion,
    [Parameter(Mandatory)]$Candidate,
    [Parameter(Mandatory)][string]$Code,
    $PublishedMaintenanceInputs = $null,
    $IndividualEngineCandidate = $null,
    [ValidateSet('4.2.1','4.2.2','4.2.3','4.3.0','4.3.1','4.4.0','4.4.2','4.5.0','4.5.2')][string]$SourceVersion='4.2.1'
  )
  $contract = Get-MIR42CriterionObservationContract -Criterion $Criterion -PublishedMaintenance:($null -ne $PublishedMaintenanceInputs) -SourceVersion $SourceVersion
  # Individual native receipts contain the direct predecessor upgrades and
  # fresh-load evidence in one authenticated input.  The Technical Seal
  # admits this representation for these maintenance releases; criterion
  # consumption must retain the same bounded version contract.
  $individualFreshInput = $null -ne $PublishedMaintenanceInputs -and $SourceVersion -cin @('4.2.3','4.3.0','4.3.1','4.4.0','4.4.2','4.5.0','4.5.2')
  $individualFreshStatus = "MIR-$SourceVersion-NINE-TARGET-MAINTENANCE-INDIVIDUAL-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED"
  $record = Read-MIR42QualificationBootstrapRecord -Path $Path -Code $Code
  $candidateManifest = $Candidate.candidate_manifest
  $source = $Candidate.source
  $candidateBound = $record.PSObject.Properties.Name -contains 'source' -and
    $record.PSObject.Properties.Name -contains 'candidate_manifest' -and
    [string]$record.source.commit -ceq [string]$source.commit -and
    [string]$record.source.tree -ceq [string]$source.tree -and
    [string]$record.source.package_source_sha256 -ceq [string]$source.package_source_sha256 -and
    [string]$record.candidate_manifest.sha256 -ceq [string]$candidateManifest.sha256 -and
    [string]$record.candidate_manifest.record_sha256 -ceq [string]$candidateManifest.record_sha256
  # Construction evidence has the package source at the manifest root, while
  # commit/tree remain under source. Bind both locations before either
  # construction-only criterion can consume the record.
  $candidateConstructionSourceBound =
    $record.PSObject.Properties.Name -contains 'source' -and
    $record.PSObject.Properties.Name -contains 'package_source_sha256' -and
    $Candidate.PSObject.Properties.Name -contains 'source' -and
    $record.source -is [object] -and $source -is [object] -and
    $record.source.PSObject.Properties.Name -contains 'commit' -and
    $record.source.PSObject.Properties.Name -contains 'tree' -and
    $source.PSObject.Properties.Name -contains 'commit' -and
    $source.PSObject.Properties.Name -contains 'tree' -and
    $source.PSObject.Properties.Name -contains 'package_source_sha256' -and
    [string]$record.source.commit -ceq [string]$source.commit -and
    [string]$record.source.tree -ceq [string]$source.tree -and
    [string]$record.package_source_sha256 -ceq [string]$source.package_source_sha256
  $candidateConstruction = $candidateConstructionSourceBound -and
    [string]$record.kind -cin @('MIR42FourTargetDeterministicCandidateManifestV1','MIR42FourTargetDeterministicCandidateManifestV2','MIR42FourTargetDeterministicCandidateManifestV3','MIR42FourTargetDeterministicCandidateManifestV4','MIR42FourTargetDeterministicCandidateManifestV5','MIR42FourTargetDeterministicCandidateManifestV6','MIR42FourTargetDeterministicCandidateManifestV7','MIR42FourTargetDeterministicCandidateManifestV9','MIR42FourTargetDeterministicCandidateManifestV10','MIR42FourTargetDeterministicCandidateManifestV12') -and
    [string]$record.record_sha256 -ceq [string]$candidateManifest.record_sha256 -and
    (Get-MIR4Sha256File -Path $Path) -ceq [string]$candidateManifest.sha256
  if ($candidateConstruction) {
    $constructionContract = Get-MIR42CandidateConstructionVersionContract -RepoRoot $mir42QualificationRoot -Manifest $record
    $candidateConstruction = [string]$constructionContract.source_version -ceq $SourceVersion
  }
  $kindAndStateValid = switch ($Criterion) {
    'fresh-exact-loads' {
      $candidateBound -and (
        ([string]$record.kind -ceq [string]$contract.kind -and [string]$record.status -ceq [string]$contract.status) -or
        ($individualFreshInput -and [string]$record.kind -ceq 'MIR42NineTargetMaintenanceIndividualRealEngineEvidenceBinderV1' -and
          [string]$record.status -ceq $individualFreshStatus -and
          $record.PSObject.Properties.Name -contains 'engine_input_kind' -and [string]$record.engine_input_kind -ceq 'individual-upgrade-receipts-and-fresh-loads')
      ) -and
        [string]$record.release_qualification -ceq 'not-performed' -and [string]$record.release_acceptance -ceq 'not-performed'
    }
    'target-omissions' {
      $candidateBound -and [string]$record.kind -ceq [string]$contract.kind -and
        [string]$record.status -ceq [string]$contract.status -and
        [string]$record.release_qualification -ceq 'not-performed'
    }
    'package-exclusion' { $candidateConstruction -and [bool]$record.build_complete }
    'deterministic-reconstruction' { $candidateConstruction -and [bool]$record.build_complete }
    'performance-telemetry' {
      if ($SourceVersion -ceq '4.3.0') {
        $candidateBound -and [string]$record.kind -ceq 'MIR430FullStartupStressObservationV1' -and
          [string]$record.status -ceq 'completed' -and [string]$record.compiler_profile -ceq 'full'
      } else {
        $candidateBound -and [string]$record.kind -ceq 'MIR42NineTargetCriterionObservationV1' -and
          [string]$record.status -ceq 'passed' -and [string]$record.criterion -ceq $Criterion -and
          [string]$record.telemetry_scope -ceq 'bounded-candidate-load-and-upgrade-resource-observation'
      }
    }
    default {
      $candidateBound -and [string]$record.kind -ceq 'MIR42NineTargetCriterionObservationV1' -and
        [string]$record.status -ceq 'passed' -and [string]$record.criterion -ceq $Criterion
    }
  }
  if (-not $kindAndStateValid) { throw "[$Code-binding] $Criterion" }
  if ($null -ne $PublishedMaintenanceInputs -and $SourceVersion -cne '4.3.0' -and -not ($SourceVersion -cin @('4.3.1','4.4.0','4.4.2','4.5.0','4.5.2') -and $Criterion -ceq 'performance-telemetry')) {
    Assert-MIR42MaintenanceCriterionObservation -Record $record -Criterion $Criterion -PublishedInputs $PublishedMaintenanceInputs
  }
  if ($Criterion -ceq 'performance-telemetry' -and $SourceVersion -ceq '4.3.0') {
    $null = Assert-MIR430FullStartupStressObservation -RepoRoot $mir42QualificationRoot -Path $Path -Candidate $Candidate -Code $Code
  } elseif ($Criterion -ceq 'performance-telemetry' -and $SourceVersion -cin @('4.3.1','4.4.0','4.4.2','4.5.0','4.5.2')) {
    if ($null -eq $IndividualEngineCandidate -or $null -eq $PublishedMaintenanceInputs) { throw "[$Code-normal-performance-engine-input]" }
    $null = Assert-MIR431NormalPerformanceTelemetryObservation -Record $record -Candidate $Candidate -IndividualEngineCandidate $IndividualEngineCandidate -PublishedMaintenanceInputs $PublishedMaintenanceInputs -Code $Code
  }
  return [pscustomobject][ordered]@{
    path = (Resolve-Path -LiteralPath $Path).Path
    sha256 = Get-MIR4Sha256File -Path $Path
    record_sha256 = [string]$record.record_sha256
  }
}

function New-MIR42NineTargetCriterionEvidence {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][ValidateSet('fresh-exact-loads','settings-profile-continuity','research-progression','migrations-two-reload','compatibility-canaries','target-omissions','performance-telemetry','package-exclusion','deterministic-reconstruction')][string]$Criterion,
    [Parameter(Mandatory)][string[]]$ObservationPaths,
    [Parameter(Mandatory)][string[]]$ObservedTargets,
    [hashtable]$NotApplicableTargetReasons = @{},
    [Parameter(Mandatory)][string]$Claim,
    [Parameter(Mandatory)][string]$KnownLimitations,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$PublishedMaintenancePredecessorManifestPath = '',
    [System.Collections.IDictionary]$PublishedMaintenanceArchiveBindings = $null
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $maintenanceRequested = -not [string]::IsNullOrWhiteSpace($PublishedMaintenancePredecessorManifestPath)
  if ($null -ne $PublishedMaintenanceArchiveBindings -and -not $maintenanceRequested) {
    throw '[mir42-criterion-maintenance-archive-bindings-scope]'
  }
  $candidateRows = Get-MIR42QualificationCandidateRows -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath
  if ([string]$candidateRows[0].scope -cne 'nine-target') { throw '[mir42-criterion-evidence-candidate-scope]' }
  $maintenanceInputs = $null
  $maintenanceSourceVersion = [string]$candidateRows[0].identity.source_version
  $null = Get-MIR42CriterionObservationContract -Criterion $Criterion -PublishedMaintenance:$maintenanceRequested -SourceVersion $maintenanceSourceVersion
  if ($maintenanceRequested) {
    Assert-MIR42MaintenanceReconciliationScope -Scope ([string]$candidateRows[0].scope) -Candidates $candidateRows
    $predecessorContract = Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion $maintenanceSourceVersion
    $metadataText = (& gh api ('repos/Julesc013/more-infinite-research/releases/tags/' + $predecessorContract.source_tag) | Out-String)
    if ($LASTEXITCODE -ne 0) { throw '[mir42-criterion-maintenance-release-readback]' }
    $maintenanceArguments = @{RepoRoot=$repo;ManifestPath=$PublishedMaintenancePredecessorManifestPath
      ReleaseMetadata=($metadataText | ConvertFrom-Json -Depth 100 -DateKind String);CandidateSourceVersion=$maintenanceSourceVersion}
    if ($null -ne $PublishedMaintenanceArchiveBindings) { $maintenanceArguments.ArchiveBindings = $PublishedMaintenanceArchiveBindings }
    $maintenanceInputs = Get-MIR42PublishedMaintenancePredecessorInputs @maintenanceArguments
  }
  $candidate = [pscustomobject][ordered]@{
    source = [pscustomobject][ordered]@{
      commit = [string]$candidateRows[0].source.commit
      tree = [string]$candidateRows[0].source.tree
      package_source_sha256 = [string]$candidateRows[0].package_source_sha256
    }
    candidate_manifest = $candidateRows[0].candidate_manifest
    source_version = $maintenanceSourceVersion
    targets = @($candidateRows | ForEach-Object { [string]$_.target })
    target_rows = @($candidateRows)
  }
  $observed = @($ObservedTargets | ForEach-Object { [string]$_ })
  $notApplicable = @(
    foreach ($target in $candidate.targets) {
      if ($NotApplicableTargetReasons.ContainsKey($target)) { [ordered]@{target=$target;reason=[string]$NotApplicableTargetReasons[$target]} }
    }
  )
  $notApplicableTargets = @($notApplicable | ForEach-Object { [string]$_.target })
  if ($observed.Count -eq 0 -or @($observed | Sort-Object -Unique).Count -ne $observed.Count -or
      @($notApplicableTargets | Sort-Object -Unique).Count -ne $notApplicableTargets.Count -or
      @($observed + $notApplicableTargets).Count -ne $candidate.targets.Count -or
      (@($observed + $notApplicableTargets | Sort-Object { [array]::IndexOf($candidate.targets, [string]$_) }) -join '|') -cne ($candidate.targets -join '|') -or
      @($notApplicable | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.reason) }).Count -ne 0) {
    throw '[mir42-criterion-evidence-target-coverage]'
  }
  if ($Criterion -ceq 'performance-telemetry' -and $maintenanceSourceVersion -ceq '4.3.0') {
    $expectedUnobserved = @($candidate.targets | Where-Object { $_ -cne 'f200' })
    if (($observed -join '|') -cne 'f200' -or ($notApplicableTargets -join '|') -cne ($expectedUnobserved -join '|')) {
      throw '[mir430-performance-criterion-target-scope]'
    }
  }
  if ($ObservationPaths.Count -eq 0) { throw '[mir42-criterion-evidence-observations-required]' }
  $individualEngineCandidate = if ($Criterion -ceq 'performance-telemetry' -and $maintenanceSourceVersion -cin @('4.3.1','4.4.0','4.4.2','4.5.0','4.5.2')) {
    New-MIR431NormalPerformanceEngineCandidate -CandidateManifestPath $CandidateManifestPath -Candidate $candidate
  } else { $null }
  $evidence = @(
    foreach ($path in $ObservationPaths) {
      Get-MIR42CriterionEvidenceObservation -Path $path -Criterion $Criterion -Candidate $candidate -Code 'mir42-criterion-evidence-observation' -PublishedMaintenanceInputs $maintenanceInputs -IndividualEngineCandidate $individualEngineCandidate -SourceVersion $maintenanceSourceVersion
    }
  )
  if (@($evidence.path | Sort-Object -Unique).Count -ne $evidence.Count -or [string]::IsNullOrWhiteSpace($Claim) -or [string]::IsNullOrWhiteSpace($KnownLimitations)) {
    throw '[mir42-criterion-evidence-input-shape]'
  }
  $output = Resolve-MIR42CriterionEvidenceOutputPath -RepoRoot $repo -Path $OutputPath
  $record = [pscustomobject][ordered]@{
    schema = 1;kind = 'MIR42NineTargetReleaseAcceptanceCriterionEvidenceV1';status = 'passed';criterion = $Criterion
    source = $candidate.source;candidate_manifest = $candidate.candidate_manifest;observed_targets = $observed;not_applicable_targets = $notApplicable
    evidence = $evidence;limits = [ordered]@{claim=$Claim;known_limitations=$KnownLimitations};record_sha256 = ''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  Write-MIR4BootstrapRecord -Record $record -Path $output | Out-Null
  $readback = Read-MIR42QualificationBootstrapRecord -Path $output -Code 'mir42-criterion-evidence-output'
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $readback) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $record)) { throw '[mir42-criterion-evidence-output-roundtrip]' }
  return $readback
}
