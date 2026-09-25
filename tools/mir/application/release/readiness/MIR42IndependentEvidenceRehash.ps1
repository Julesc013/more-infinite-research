Set-StrictMode -Version Latest

$mir42IndependentRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
. (Join-Path $mir42IndependentRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $mir42IndependentRoot 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $mir42IndependentRoot 'tools/lib/validation/FactorioVersionPolicy.ps1')

$script:MIR42IndependentTargets = @('f210', 'f200', 'f110', 'f100')
$script:MIR42IndependentLines = [ordered]@{ f210 = '2.1'; f200 = '2.0'; f110 = '1.1'; f100 = '1.0' }
$script:MIR42IndependentEngines = [ordered]@{
  f210 = 'C:/Program Files/Steam/steamapps/common/Factorio/bin/x64/factorio.exe'
  f200 = 'D:/Programs/Factorio/2.0/bin/x64/factorio.exe'
  f110 = 'D:/Programs/Factorio/1.1/bin/x64/factorio.exe'
  f100 = 'D:/Programs/Factorio/1.0/bin/x64/factorio.exe'
}

function Read-MIR42IndependentRecord {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "[$Code-missing]" }
  try { $record = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100 -DateKind String }
  catch { throw "[$Code-json]" }
  if (-not (Test-MIR4BootstrapRecordHash -Record $record)) { throw "[$Code-hash]" }
  return $record
}

function Resolve-MIR42IndependentChild {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Relative,[Parameter(Mandatory)][string]$Code)
  if ([IO.Path]::IsPathRooted($Relative) -or [string]::IsNullOrWhiteSpace($Relative)) { throw "[$Code-path]" }
  $rootPath = [IO.Path]::GetFullPath($Root)
  $path = [IO.Path]::GetFullPath((Join-Path $rootPath $Relative))
  $prefix = $rootPath.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if (-not $path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw "[$Code-escape]" }
  $null = Assert-MIR4NoReparseAncestors -Root $rootPath -Path $path
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[$Code-missing]" }
  return $path
}

function Assert-MIR42IndependentFourRows {
  param([Parameter(Mandatory)]$Rows,[Parameter(Mandatory)][string]$Code)
  $ids = @($Rows | ForEach-Object { [string]$_.target })
  if ($ids.Count -ne 4 -or ($ids -join '|') -cne ($script:MIR42IndependentTargets -join '|')) { throw "[$Code-targets]" }
}

function Get-MIR42IndependentEngine {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)]$Qualified)
  $path = [string]$script:MIR42IndependentEngines[$Target]
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir42-independent-engine-missing] $Target" }
  $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  $version = [Diagnostics.FileVersionInfo]::GetVersionInfo((Resolve-Path -LiteralPath $path).Path).FileVersion
  if ([string]$Qualified.environment.binary_sha256 -cne $actualHash -or [string]$Qualified.environment.version -cne $version) {
    throw "[mir42-independent-engine-identity] $Target"
  }
  if ($Target -ceq 'f210') {
    $channel = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'spec/engines/mir4-factorio-2.1-experimental-channel-v1.json') | ConvertFrom-Json -Depth 100 -DateKind String
    if ([string]$channel.current_review.binary_sha256 -cne $actualHash -or [string]$channel.current_review.file_version -cne $version) {
      throw '[mir42-independent-f210-channel]'
    }
  } else {
    $lock = Get-MIR4FixedFactorioEngineLock -Target $Target -RepoRoot $RepoRoot
    if ([string]$lock.binary_sha256 -cne $actualHash -or [string]$lock.file_version -cne $version) {
      throw "[mir42-independent-fixed-engine] $Target"
    }
  }
  return [pscustomobject][ordered]@{ path = (Resolve-Path -LiteralPath $path).Path; version = $version; binary_sha256 = $actualHash }
}

function Invoke-MIR42FourTargetIndependentEvidenceRehash {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$QualificationPath,
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
  $evaluatorRelative = 'tools/mir/application/release/readiness/MIR42IndependentEvidenceRehash.ps1'
  $evaluatorDirty = @(& git -C $mir42IndependentRoot status --porcelain --untracked-files=no 2>$null)
  if ($LASTEXITCODE -ne 0 -or $evaluatorDirty.Count -ne 0) { throw '[mir42-independent-evaluator-dirty]' }
  $build = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
  $output = if ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot)) }
  $null = Assert-MIR4DescendantPath -Root $build -Path $output
  $null = Assert-MIR4NoReparseAncestors -Root $repo -Path $output
  if ((Test-Path -LiteralPath $output -PathType Leaf) -or ((Test-Path -LiteralPath $output -PathType Container) -and @(Get-ChildItem -LiteralPath $output -Force).Count -ne 0)) { throw '[mir42-independent-output-not-empty]' }

  $builderPath = (Resolve-Path -LiteralPath $CandidateManifestPath).Path
  $builderRoot = Split-Path -Parent $builderPath
  $builder = Read-MIR42IndependentRecord -Path $builderPath -Code 'mir42-independent-builder'
  $builderSchema = Join-Path $mir42IndependentRoot 'spec/schemas/mir42-four-target-deterministic-candidate-manifest-v1.schema.json'
  if (-not (Get-Content -Raw -LiteralPath $builderPath | Test-Json -SchemaFile $builderSchema)) {
    throw '[mir42-independent-builder-schema]'
  }
  $qualificationPathResolved = (Resolve-Path -LiteralPath $QualificationPath).Path
  $qualification = Read-MIR42IndependentRecord -Path $qualificationPathResolved -Code 'mir42-independent-qualification'
  if ([string]$builder.kind -cne 'MIR42FourTargetDeterministicCandidateManifestV1' -or
      [string]$builder.status -cne 'private-deterministic-four-target-candidate-built-unqualified' -or
      -not [bool]$builder.build_complete -or @($builder.failures).Count -ne 0 -or
      [string]$qualification.kind -cne 'MIR42FourTargetEvidenceReconciliationV1' -or
      [string]$qualification.status -cne 'MIR-4.2-FOUR-TARGET-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED' -or
      -not [bool]$qualification.all_four_targets_required -or [bool]$qualification.cross_target_substitution -or
      [int]$qualification.factorio_processes -ne 0 -or [string]$qualification.release_qualification -cne 'not-performed' -or
      [string]$qualification.independent_verification -cne 'not-performed' -or [bool]$qualification.publication_authorized) {
    throw '[mir42-independent-input-state]'
  }
  if ([string]$qualification.candidate_manifest.sha256 -cne (Get-MIR4Sha256File -Path $builderPath) -or
      [string]$qualification.candidate_manifest.record_sha256 -cne [string]$builder.record_sha256) {
    throw '[mir42-independent-manifest-binding]'
  }
  Assert-MIR42IndependentFourRows -Rows @($builder.targets) -Code 'mir42-independent-builder'
  Assert-MIR42IndependentFourRows -Rows @($qualification.targets) -Code 'mir42-independent-qualification'

  $commit = ([string](& git -C $repo rev-parse HEAD)).Trim()
  $tree = ([string](& git -C $repo rev-parse 'HEAD^{tree}')).Trim()
  $packageSource = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
  if ([string]$builder.source.commit -cne $commit -or [string]$builder.source.tree -cne $tree -or
      [string]$qualification.source.commit -cne $commit -or [string]$qualification.source.tree -cne $tree -or
      [string]$builder.package_source_sha256 -cne $packageSource) {
    throw '[mir42-independent-source-drift]'
  }
  $predecessors = [ordered]@{ f210=$F210PredecessorZip;f200=$F200PredecessorZip;f110=$F110PredecessorZip;f100=$F100PredecessorZip }
  $receipts = [ordered]@{ f210=$F210UpgradeReceipt;f200=$F200UpgradeReceipt;f110=$F110UpgradeReceipt;f100=$F100UpgradeReceipt }
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($target in $script:MIR42IndependentTargets) {
    $summary = @($builder.targets | Where-Object { [string]$_.target -ceq $target })[0]
    $qualified = @($qualification.targets | Where-Object { [string]$_.target -ceq $target })[0]
    if ([string]$qualified.status -cne 'reconciled' -or [string]$qualified.qualification -cne 'not-performed') {
      throw "[mir42-independent-reconciliation-state] $target"
    }
    $rowPath = Resolve-MIR42IndependentChild -Root $builderRoot -Relative ([string]$summary.target_row_path) -Code "mir42-independent-row-$target"
    $row = Read-MIR42IndependentRecord -Path $rowPath -Code "mir42-independent-row-$target"
    $assetPath = Resolve-MIR42IndependentChild -Root $builderRoot -Relative ([string]$summary.asset.path) -Code "mir42-independent-asset-$target"
    $archive = Get-MIR4ArchiveInventory -Path $assetPath
    $identity = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $repo -Target $target -SourceVersion '4.2.0'
    $forbidden = @($archive.entries | Where-Object { ([string]$_.path).Replace('\','/') -match '^(?:[.]mir|[.]codex|[.]github|build|dist|docs|fixtures|scripts|tests)(?:/|$)|^AGENTS[.]md$' })
    if ($forbidden.Count -ne 0) { throw "[mir42-independent-package-surface] $target" }
    if ([string]$row.target -cne $target -or [string]$row.source.commit -cne $commit -or
        [string]$row.source.tree -cne $tree -or -not [bool]$row.deterministic_archive_bytes -or
        [string]$row.package_source_sha256 -cne $packageSource -or
        [string]$row.build_a_sha256 -cne [string]$row.build_b_sha256 -or
        [string]$row.asset.sha256 -cne [string]$summary.asset.sha256 -or
        [string]$row.asset.sha256 -cne [string]$archive.archive_sha256 -or
        [string]$row.content_sha256 -cne [string]$archive.content_sha256 -or
        [int]$row.entry_count -ne [int]$archive.entry_count -or
        [string]$row.distribution_version -cne [string]$identity.distribution_version -or
        [string]$archive.root -cne [string]$identity.distribution_root -or
        [string]$qualified.candidate.sha256 -cne [string]$archive.archive_sha256 -or
        [string]$qualified.candidate.content_sha256 -cne [string]$archive.content_sha256 -or
        [int]$qualified.candidate.entry_count -ne [int]$archive.entry_count -or
        [string]$qualified.candidate_target_row.sha256 -cne (Get-MIR4Sha256File -Path $rowPath) -or
        [string]$qualified.candidate_manifest.sha256 -cne (Get-MIR4Sha256File -Path $builderPath) -or
        [string]$qualified.candidate_manifest.record_sha256 -cne [string]$builder.record_sha256) {
      throw "[mir42-independent-candidate-binding] $target"
    }
    $info = Read-MIR4ArchiveText -Path $assetPath -RelativePath 'info.json' | ConvertFrom-Json -Depth 20 -DateKind String
    if ([string]$info.version -cne [string]$identity.distribution_version -or
        [string]$info.factorio_version -cne [string]$script:MIR42IndependentLines[$target] -or
        [string]$info.name -cne 'more-infinite-research') { throw "[mir42-independent-metadata] $target" }
    $engine = Get-MIR42IndependentEngine -RepoRoot $repo -Target $target -Qualified $qualified
    $predecessorPath = (Resolve-Path -LiteralPath ([string]$predecessors[$target])).Path
    $predecessor = Get-MIR4ArchiveInventory -Path $predecessorPath
    if ([string]$predecessor.archive_sha256 -cne [string]$qualified.predecessor.archive.sha256) { throw "[mir42-independent-predecessor] $target" }
    $receiptPath = (Resolve-Path -LiteralPath ([string]$receipts[$target])).Path
    if ((Get-MIR4Sha256File -Path $receiptPath) -cne [string]$qualified.harness.upgrade_receipt.sha256) { throw "[mir42-independent-receipt-hash] $target" }
    $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100 -DateKind String
    if ([string]$receipt.status -cne 'passed' -or [string]$receipt.to.sha256 -cne [string]$archive.archive_sha256 -or
        [string]$receipt.from.sha256 -cne [string]$predecessor.archive_sha256 -or
        [string]$receipt.factorio_binary_sha256 -cne [string]$engine.binary_sha256) { throw "[mir42-independent-upgrade-binding] $target" }
    if ([bool]$qualified.harness.source_commit_matches_candidate -ne ([string]$receipt.git_commit -ceq $commit)) {
      throw "[mir42-independent-receipt-source-report] $target"
    }
    $assertions = @($receipt.assertions | ForEach-Object { [string]$_ })
    foreach ($required in @('exact-candidate-normal-mod-directory-load','upgraded-save-reload-passed','upgraded-save-second-reload-passed')) {
      if ($required -notin $assertions -or $required -notin @($qualified.harness.assertions)) { throw "[mir42-independent-assertion] $target/$required" }
    }
    foreach ($log in @($qualified.harness.logs)) {
      $path = Resolve-MIR42IndependentChild -Root (Split-Path -Parent $receiptPath) -Relative ([string]$log.path) -Code "mir42-independent-log-$target"
      if ((Get-MIR4Sha256File -Path $path) -cne [string]$log.sha256) { throw "[mir42-independent-log-hash] $target" }
    }
    $rows.Add([pscustomobject][ordered]@{
      target = $target
      distribution_version = [string]$identity.distribution_version
      archive = [pscustomobject][ordered]@{ path = $assetPath; sha256 = [string]$archive.archive_sha256; content_sha256 = [string]$archive.content_sha256; entry_count = [int]$archive.entry_count }
      engine = $engine
      predecessor_sha256 = [string]$predecessor.archive_sha256
      upgrade_receipt_sha256 = Get-MIR4Sha256File -Path $receiptPath
      verified_logs = @($qualified.harness.logs).Count
      status = 'reconciled'
      verification_scope = 'independent-rehash-of-supplied-candidate-and-upgrade-evidence-only'
    })
  }

  $result = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42FourTargetIndependentEvidenceRehashV1'
    status = 'MIR-4.2-FOUR-TARGET-INDEPENDENT-EVIDENCE-REHASH-PASSED-PRIVATE-UNQUALIFIED'
    source = [pscustomobject][ordered]@{ commit=$commit;tree=$tree;package_source_sha256=$packageSource }
    evaluator = [pscustomobject][ordered]@{
      implementation = $evaluatorRelative
      git_commit = ([string](& git -C $mir42IndependentRoot rev-parse HEAD)).Trim()
      sha256 = Get-MIR4Sha256File -Path (Join-Path $mir42IndependentRoot $evaluatorRelative)
    }
    candidate_manifest = [pscustomobject][ordered]@{ path=$builderPath;sha256=Get-MIR4Sha256File -Path $builderPath;record_sha256=[string]$builder.record_sha256 }
    qualification = [pscustomobject][ordered]@{ path=$qualificationPathResolved;sha256=Get-MIR4Sha256File -Path $qualificationPathResolved;record_sha256=[string]$qualification.record_sha256 }
    targets = @($rows)
    all_four_targets_required = $true
    factorio_processes = 0
    release_qualification = 'not-performed'
    independent_release_acceptance = 'not-performed'
    technical_seal = 'not-performed'
    signing_authorized = $false
    publication_authorized = $false
    record_sha256 = ''
  }
  New-Item -ItemType Directory -Force -Path $output | Out-Null
  $path = Join-Path $output 'independent-evidence-rehash.json'
  Write-MIR4BootstrapRecord -Record $result -Path $path | Out-Null
  return $result
}
