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

$script:MIR42QualificationTargets = @('f210', 'f200', 'f110', 'f100')
$script:MIR42QualificationLines = [ordered]@{ f210 = '2.1'; f200 = '2.0'; f110 = '1.1'; f100 = '1.0' }
$script:MIR42QualificationAssertions = @(
  'exact-candidate-normal-mod-directory-load',
  'upgraded-save-reload-passed',
  'upgraded-save-second-reload-passed'
)

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

function Get-MIR42QualificationCandidateRows {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath
  )

  $manifestPath = (Resolve-Path -LiteralPath $CandidateManifestPath).Path
  $root = Split-Path -Parent $manifestPath
  $manifest = Read-MIR42QualificationBootstrapRecord -Path $manifestPath -Code 'mir42-qualification-candidate-manifest'
  if ([string]$manifest.kind -cne 'MIR42FourTargetCandidateManifestV1' -or
      [string]$manifest.status -cne 'private-deterministic-four-target-candidate-built-unqualified' -or
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
  $targets = @($manifest.targets)
  if ($targets.Count -ne 4 -or (@($targets.target) -join '|') -cne ($script:MIR42QualificationTargets -join '|')) {
    throw '[mir42-qualification-candidate-target-set]'
  }

  $rows = [Collections.Generic.List[object]]::new()
  foreach ($target in $script:MIR42QualificationTargets) {
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

    $identity = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $RepoRoot -Target $target -SourceVersion '4.2.0'
    if ([string]$row.distribution_version -cne [string]$identity.distribution_version -or
        [string]$summary[0].distribution_version -cne [string]$identity.distribution_version) {
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
    $rows.Add([pscustomobject][ordered]@{
      target = $target
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

function Get-MIR42QualificationEnvironment {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)]$Receipt)

  $receiptVersion = [string]$Receipt.factorio_binary_version
  $receiptSha = [string]$Receipt.factorio_binary_sha256
  if ($receiptVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' -or $receiptSha -notmatch '^[A-F0-9]{64}$') {
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
  foreach ($required in $script:MIR42QualificationAssertions) {
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

function Invoke-MIR42FourTargetExactCandidateQualification {
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

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $output = Assert-MIR42QualificationOutputRoot -RepoRoot $repo -OutputRoot $OutputRoot
  $null = Get-MIR42QualificationCurrentSource -RepoRoot $repo
  $candidates = Get-MIR42QualificationCandidateRows -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath
  $predecessors = [ordered]@{
    f210 = $F210PredecessorZip
    f200 = $F200PredecessorZip
    f110 = $F110PredecessorZip
    f100 = $F100PredecessorZip
  }
  $receipts = [ordered]@{
    f210 = $F210UpgradeReceipt
    f200 = $F200UpgradeReceipt
    f110 = $F110UpgradeReceipt
    f100 = $F100UpgradeReceipt
  }

  $rows = [Collections.Generic.List[object]]::new()
  foreach ($candidate in $candidates) {
    $target = [string]$candidate.target
    $upgrade = Get-MIR42QualificationUpgradeReceipt -RepoRoot $repo -Target $target -Path ([string]$receipts[$target]) -Candidate $candidate
    $predecessor = Get-MIR42QualificationPredecessor -Target $target -Path ([string]$predecessors[$target]) -Receipt $upgrade.receipt_object
    $rows.Add([pscustomobject][ordered]@{
      target = $target
      target_id = [string]$candidate.identity.target_id
      distribution_version = [string]$candidate.identity.distribution_version
      status = 'passed'
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
        upgrade_receipt = $upgrade.receipt
        assertions = $upgrade.assertions
        logs = $upgrade.logs
      }
      qualification = 'passed-exact-candidate-base-direct-predecessor-two-reload'
      independent_verification = 'not-performed'
      technical_seal = 'not-performed'
      publication_authorized = $false
    })
  }

  $result = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42FourTargetExactCandidateQualificationV1'
    status = 'MIR-4.2-FOUR-TARGET-EXACT-CANDIDATE-QUALIFICATION-PASSED-PRIVATE-UNSEALED'
    qualification_scope = 'exact candidate ZIP base-default normal-mod-directory load, direct predecessor upgrade, and two reloads on recorded target environment'
    source = [pscustomobject][ordered]@{
      commit = [string]$candidates[0].source.commit
      tree = [string]$candidates[0].source.tree
      package_source_sha256 = [string]$candidates[0].package_source_sha256
    }
    candidate_manifest = $candidates[0].candidate_manifest
    targets = @($rows)
    all_four_targets_required = $true
    cross_target_substitution = $false
    independent_verification = 'not-performed'
    technical_seal = 'not-performed'
    source_freeze_authorized = $false
    signing_authorized = $false
    tagging_authorized = $false
    publication_authorized = $false
    nonclaims = @(
      'No source freeze, technical seal, protected signing, protected main promotion, maintainer gameplay GO, tagging, or publication authority is established.',
      'The qualification scope is limited to the exact candidate ZIPs and recorded base-default direct-predecessor engine evidence.'
    )
    record_sha256 = ''
  }
  $path = Resolve-MIR4ArtifactPath -OutputRoot $output -RelativePath 'qualification.json'
  Write-MIR4BootstrapRecord -Record $result -Path $path | Out-Null
  return $result
}
