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
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][ValidateSet('f017','f016','f015','f014','f013')][string]$Target)
  $identity = Get-MIR42ReleaseTargetIdentity -RepoRoot $RepoRoot -Target $Target
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
      [string]$record.distribution_version -cne [string]$identity.distribution_version -or
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
  $inventory = Get-MIR4ArchiveInventory -Path $predecessorPath
  if ([string]$inventory.archive_sha256 -cne [string]$seal.archive_sha256 -or [int64]$inventory.bytes -ne [int64]$seal.bytes -or
      [string]$inventory.content_sha256 -cne [string]$seal.content_sha256 -or [int]$inventory.entry_count -ne [int]$seal.entries) {
    throw "[mir42-qualification-historical-predecessor-binding] $Target"
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
  $schema = Join-Path $mir42QualificationRoot 'spec/schemas/mir42-four-target-deterministic-candidate-manifest-v1.schema.json'
  if (-not (Get-Content -Raw -LiteralPath $manifestPath | Test-Json -SchemaFile $schema)) {
    throw '[mir42-qualification-candidate-manifest-schema]'
  }
  $targets = @($manifest.targets)
  $scope = Get-MIR42QualificationTargetScope -Rows $targets -Code 'mir42-qualification-candidate'
  $contract = Get-MIR42QualificationScopeContract -Scope $scope
  if ([string]$manifest.kind -cne 'MIR42FourTargetDeterministicCandidateManifestV1' -or
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
    if ([string]$row.kind -cne 'MIR42FourTargetCandidateRowV1' -or
        [string]$row.status -cne 'accepted-private-deterministic-unqualified' -or
        [string]$row.target -cne $target -or
        [string]$row.source.commit -cne [string]$manifest.source.commit -or
        [string]$row.source.tree -cne [string]$manifest.source.tree -or
        [string]$row.package_source_sha256 -cne [string]$manifest.package_source_sha256 -or
        -not [bool]$row.deterministic_archive_bytes -or
        -not [bool]$row.package_excluded_surface) {
      throw "[mir42-qualification-target-row-binding] $target"
    }

    $identity = Get-MIR42ReleaseTargetIdentity -RepoRoot $RepoRoot -Target $target
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
      $historical = Get-MIR42QualificationHistoricalAuthority -RepoRoot $RepoRoot -Target $target
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
    [Parameter(Mandatory)]$Receipt
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
    $historical = Get-MIR42QualificationHistoricalAuthority -RepoRoot $RepoRoot -Target $Target
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
  if ([int]$receipt.schema -ne 2 -or [string]$receipt.status -cne 'passed' -or
      [string]$receipt.archetype -cne 'base-default' -or
      [string]$receipt.git_commit -notmatch '^[a-f0-9]{40}$' -or
      [string]$receipt.to.version -cne [string]$Candidate.identity.distribution_version -or
      [string]$receipt.to.sha256 -cne [string]$Candidate.archive.sha256) {
    throw "[mir42-qualification-upgrade-receipt-binding] $Target"
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

function Invoke-MIR42EvidenceReconciliationShared {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][hashtable]$PredecessorZips,
    [Parameter(Mandatory)][hashtable]$UpgradeReceipts,
    [Parameter(Mandatory)][string]$OutputRoot,
    [ValidateSet('four-target','nine-target')][string]$RequiredScope
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
  $output = Assert-MIR42QualificationOutputRoot -RepoRoot $repo -OutputRoot $OutputRoot

  $rows = [Collections.Generic.List[object]]::new()
  foreach ($candidate in $candidates) {
    $target = [string]$candidate.target
    $upgrade = Get-MIR42QualificationUpgradeReceipt -RepoRoot $repo -Target $target -Path ([string]$UpgradeReceipts[$target]) -Candidate $candidate
    if ($target -in $script:MIR42QualificationHistoricalTargets) {
      $providedPredecessor = (Resolve-Path -LiteralPath ([string]$PredecessorZips[$target])).Path
      if (-not $providedPredecessor.Equals([string]$candidate.historical.predecessor_path,[StringComparison]::OrdinalIgnoreCase)) {
        throw "[mir42-reconciliation-historical-predecessor-path] $target"
      }
    }
    $predecessor = Get-MIR42QualificationPredecessor -Target $target -Path ([string]$PredecessorZips[$target]) -Receipt $upgrade.receipt_object
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
    kind = [string]$contract.kind
    status = [string]$contract.status
    reconciliation_scope = if ($scope -ceq 'four-target') { 'The four supplied upgrade receipts and logs match the exact candidate ZIP bytes and supplied predecessor archives; this command does not execute Factorio or establish governed predecessor custody.' } else { 'The nine supplied upgrade receipts and logs match the exact candidate ZIP bytes, modern predecessor archives, and historical terminal-seal predecessor chains; this command does not execute Factorio or establish release qualification.' }
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
    [Parameter(Mandatory)][string]$OutputRoot
  )
  $manifest = Read-MIR42QualificationBootstrapRecord -Path $CandidateManifestPath -Code 'mir42-reconciliation-entrypoint-candidate'
  if ((Get-MIR42QualificationTargetScope -Rows @($manifest.targets) -Code 'mir42-reconciliation-entrypoint') -cne 'nine-target') {
    throw '[mir42-reconciliation-entrypoint-target-scope]'
  }
  return Invoke-MIR42EvidenceReconciliationShared -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath -PredecessorZips $PredecessorZips -UpgradeReceipts $UpgradeReceipts -OutputRoot $OutputRoot -RequiredScope 'nine-target'
}

$script:MIR42ReleaseAcceptanceCriteria = @(
  'fresh-exact-loads', 'settings-profile-continuity', 'research-progression', 'migrations-two-reload',
  'compatibility-canaries', 'target-omissions', 'performance-telemetry', 'package-exclusion',
  'deterministic-reconstruction'
)

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

function Get-MIR42CriterionEvidenceObservation {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Criterion,
    [Parameter(Mandatory)]$Candidate,
    [Parameter(Mandatory)][string]$Code
  )
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
  $candidateConstruction = [string]$record.kind -ceq 'MIR42FourTargetDeterministicCandidateManifestV1' -and
    [string]$record.record_sha256 -ceq [string]$candidateManifest.record_sha256
  $kindAndStateValid = switch ($Criterion) {
    'fresh-exact-loads' {
      $candidateBound -and [string]$record.kind -ceq 'MIR42NineTargetRealEngineEvidenceBinderV1' -and
        [string]$record.status -ceq 'MIR-4.2-NINE-TARGET-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED' -and
        [string]$record.release_qualification -ceq 'not-performed' -and [string]$record.release_acceptance -ceq 'not-performed'
    }
    'target-omissions' {
      $candidateBound -and [string]$record.kind -ceq 'MIR42NineTargetEvidenceReconciliationV1' -and
        [string]$record.status -ceq 'MIR-4.2-NINE-TARGET-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED' -and
        [string]$record.release_qualification -ceq 'not-performed'
    }
    'package-exclusion' { $candidateConstruction -and [bool]$record.build_complete }
    'deterministic-reconstruction' { $candidateConstruction -and [bool]$record.build_complete }
    'performance-telemetry' {
      $candidateBound -and [string]$record.kind -ceq 'MIR42NineTargetCriterionObservationV1' -and
        [string]$record.status -ceq 'passed' -and [string]$record.criterion -ceq $Criterion -and
        [string]$record.telemetry_scope -ceq 'bounded-candidate-load-and-upgrade-resource-observation'
    }
    default {
      $candidateBound -and [string]$record.kind -ceq 'MIR42NineTargetCriterionObservationV1' -and
        [string]$record.status -ceq 'passed' -and [string]$record.criterion -ceq $Criterion
    }
  }
  if (-not $kindAndStateValid) { throw "[$Code-binding] $Criterion" }
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
    [Parameter(Mandatory)][string]$OutputPath
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $candidateRows = Get-MIR42QualificationCandidateRows -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath
  if ([string]$candidateRows[0].scope -cne 'nine-target') { throw '[mir42-criterion-evidence-candidate-scope]' }
  $candidate = [pscustomobject][ordered]@{
    source = $candidateRows[0].source
    candidate_manifest = $candidateRows[0].candidate_manifest
    targets = @($candidateRows | ForEach-Object { [string]$_.target })
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
  if ($ObservationPaths.Count -eq 0) { throw '[mir42-criterion-evidence-observations-required]' }
  $evidence = @(
    foreach ($path in $ObservationPaths) {
      Get-MIR42CriterionEvidenceObservation -Path $path -Criterion $Criterion -Candidate $candidate -Code 'mir42-criterion-evidence-observation'
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
