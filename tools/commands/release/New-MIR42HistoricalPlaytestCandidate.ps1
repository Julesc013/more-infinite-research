param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [ValidateSet('f017')][string]$Target = 'f017',
  [ValidatePattern('^[A-Z0-9][A-Z0-9.-]*$')][string]$CandidateId = 'MIR42-HISTORICAL',
  [ValidateRange(2, 3)][int]$Repetitions = 2,
  [string]$OutputRoot = 'build/mir42-historical-playtest',
  [switch]$Check
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')

function Get-MIR42HistoricalTargetRecord {
  param([string]$TargetId)
  $path = Join-Path $repo "targets/historical/$TargetId/target.json"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir42-historical-target-record-missing] $TargetId" }
  $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 50
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42HistoricalPlaytestTargetV1' -or
      [string]$record.target -cne $TargetId -or [string]::IsNullOrWhiteSpace([string]$record.record_sha256) -or
      -not (Test-MIR4BootstrapRecordHash -Record $record)) {
    throw "[mir42-historical-target-record-invalid] $TargetId"
  }
  if ([string]$record.base_materializer_target -cne 'f100' -or [bool]$record.public_output_authorized -or [bool]$record.publication_authorized) {
    throw "[mir42-historical-target-boundary] $TargetId"
  }
  return [pscustomobject]@{ path = $path; record = $record }
}

function Assert-MIR42HistoricalSource {
  param($Adapter)
  $relative = [string]$Adapter.source_path
  if ($relative -notmatch '^source/') { throw "[mir42-historical-adapter-boundary] $relative" }
  $full = [IO.Path]::GetFullPath((Join-Path $repo $relative))
  $prefix = $repo.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
    throw "[mir42-historical-adapter-source-missing] $relative"
  }
  $bytes = [IO.File]::ReadAllBytes($full)
  if ([int64]$bytes.Length -ne [int64]$Adapter.source_bytes -or
      (Get-MIR4Sha256Bytes -Bytes $bytes) -cne [string]$Adapter.source_sha256) {
    throw "[mir42-historical-adapter-source-drift] $relative"
  }
  return $bytes
}

function Copy-MIR42HistoricalAdapter {
  param([string]$Tree, $Record)
  foreach ($adapter in @($Record.adapter_files)) {
    $output = [string]$adapter.output_path
    Assert-MIR4PortableArchivePath -Path $output
    $destination = [IO.Path]::GetFullPath((Join-Path $Tree $output))
    $treePrefix = $Tree.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $destination.StartsWith($treePrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $destination -PathType Leaf)) {
      throw "[mir42-historical-adapter-output-missing] $output"
    }
    [IO.File]::WriteAllBytes($destination, (Assert-MIR42HistoricalSource -Adapter $adapter))
  }
  foreach ($patch in @($Record.patches)) {
    $output = [string]$patch.output_path
    Assert-MIR4PortableArchivePath -Path $output
    $destination = [IO.Path]::GetFullPath((Join-Path $Tree $output))
    $treePrefix = $Tree.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $destination.StartsWith($treePrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $destination -PathType Leaf)) {
      throw "[mir42-historical-patch-output-missing] $output"
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash -cne [string]$patch.base_sha256) {
      throw "[mir42-historical-patch-base-drift] $output"
    }
    $original = [IO.File]::ReadAllText($destination)
    $find = [string]$patch.find
    $count = [regex]::Matches($original, [regex]::Escape($find)).Count
    if ($count -ne 1) { throw "[mir42-historical-patch-anchor] ${output}:$count" }
    [IO.File]::WriteAllText($destination, $original.Replace($find, [string]$patch.replace), [Text.UTF8Encoding]::new($false))
  }
}

$targetState = Get-MIR42HistoricalTargetRecord -TargetId $Target
$record = $targetState.record
$output = if ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot)) }
$buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
$buildPrefix = $buildRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (-not $output.StartsWith($buildPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "[mir42-historical-output-boundary] $output" }
New-Item -ItemType Directory -Force -Path $output | Out-Null

$sourceCommit = (& git -C $repo rev-parse HEAD).Trim()
$sourceTree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$rows = @()
foreach ($letter in @('A', 'B', 'C') | Select-Object -First $Repetitions) {
  $base = New-MIR4TargetPackage -RepoRoot $repo -Target ([string]$record.base_materializer_target) `
    -CandidateId "$CandidateId-BASE-$letter" -OutputRoot (Join-Path $output 'base')
  $candidateParent = Resolve-MIR4ArtifactPath -OutputRoot $output -RelativePath "$Target/$CandidateId/$letter"
  Remove-MIR4BuildTree -OutputRoot $output -Path $candidateParent
  New-Item -ItemType Directory -Force -Path $candidateParent | Out-Null
  $tree = Join-Path $candidateParent "more-infinite-research_$([string]$record.distribution_version)"
  Copy-Item -LiteralPath ([string]$base.tree_path) -Destination $tree -Recurse
  Copy-MIR42HistoricalAdapter -Tree $tree -Record $record
  $info = Get-Content -Raw -LiteralPath (Join-Path $tree 'info.json') | ConvertFrom-Json -Depth 20
  if ([string]$info.name -cne 'more-infinite-research' -or [string]$info.version -cne [string]$record.distribution_version -or
      [string]$info.factorio_version -cne [string]$record.factorio_line) {
    throw "[mir42-historical-info-identity] $Target"
  }
  $archive = Join-Path $candidateParent "more-infinite-research_$([string]$record.distribution_version).zip"
  Write-MIR4DeterministicRawTreeArchive -SourceRoot $tree -EntryRoot (Split-Path -Leaf $tree) -OutputPath $archive -ContainmentRoot $output
  $inventory = Get-MIR4ArchiveInventory -Path $archive
  $forbidden = @($inventory.entries | Where-Object { $_.path -match '^(?:\.mir|\.codex|\.github|build|dist|docs|tests|tools|scripts)/' })
  if ($forbidden.Count -gt 0) { throw "[mir42-historical-package-forbidden-path] $Target" }
  $rows += [pscustomobject][ordered]@{
    id = $letter
    archive_path = [IO.Path]::GetRelativePath($repo, $archive).Replace('\', '/')
    archive_sha256 = [string]$inventory.archive_sha256
    content_sha256 = [string]$inventory.content_sha256
    entry_count = [int]$inventory.entry_count
  }
}
if (@($rows.archive_sha256 | Sort-Object -Unique).Count -ne 1 -or @($rows.content_sha256 | Sort-Object -Unique).Count -ne 1) {
  throw "[mir42-historical-nondeterministic] $Target"
}
$distribution = Resolve-MIR4ArtifactPath -OutputRoot $output -RelativePath "distributions/more-infinite-research_$([string]$record.distribution_version).zip"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $distribution) | Out-Null
Copy-Item -LiteralPath (Join-Path $repo ([string]$rows[0].archive_path)) -Destination $distribution -Force
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $distribution).Hash -cne [string]$rows[0].archive_sha256) { throw "[mir42-historical-distribution-copy] $Target" }

$manifest = [pscustomobject][ordered]@{
  schema = 1
  kind = 'MIR42HistoricalPlaytestCandidateManifestV1'
  status = 'built-private-historical-unqualified'
  target = $Target
  maturity = [string]$record.maturity
  source = [ordered]@{ commit = $sourceCommit; tree = $sourceTree; canonical_base_target = [string]$record.base_materializer_target }
  target_record = [ordered]@{ path = [IO.Path]::GetRelativePath($repo, $targetState.path).Replace('\', '/'); sha256 = [string]$record.record_sha256 }
  factorio_line = [string]$record.factorio_line
  distribution_version = [string]$record.distribution_version
  engine = $record.engine
  predecessor = $record.predecessor
  builds = $rows
  distribution = [ordered]@{ path = [IO.Path]::GetRelativePath($repo, $distribution).Replace('\', '/'); sha256 = [string]$rows[0].archive_sha256; content_sha256 = [string]$rows[0].content_sha256; entry_count = [int]$rows[0].entry_count }
  assertions = @('current-canonical-f100-base-materialization', 'target-specific-profile-adapter', 'target-specific-metadata', 'bounded-research-cost-publication-omission', 'byte-identical-repeated-builds', 'package-path-exclusion')
  exact_engine_runtime = 'not-run'
  public_output_authorized = $false
  publication_authorized = $false
  record_sha256 = ''
}
$manifest.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $manifest
$manifestPath = Resolve-MIR4ArtifactPath -OutputRoot $output -RelativePath "manifests/$Target.json"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $manifestPath) | Out-Null
$manifest | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $manifestPath -Encoding utf8
if ($Check) {
  $current = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 50
  if (-not (Test-MIR4BootstrapRecordHash -Record $current) -or [string]$current.distribution.sha256 -cne [string]$rows[0].archive_sha256) {
    throw "[mir42-historical-manifest-check] $Target"
  }
}
$manifest
