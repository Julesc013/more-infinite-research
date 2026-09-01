Set-StrictMode -Version Latest

$mir4ShadowLoadRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).Path
if (-not (Get-Command Get-MIR4ArchiveInventory -ErrorAction SilentlyContinue) -or
    -not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue) -or
    -not (Get-Command Read-MIR4ArchiveBytes -ErrorAction SilentlyContinue) -or
    -not (Get-Command Write-MIR4DeterministicRawTreeArchive -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4ShadowLoadRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}

function Get-MIR4ShadowRepoRoot {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Import-MIR4ShadowMaterializerDependencies {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  foreach ($name in @('Get-MIR4ArchiveInventory','Test-MIR4BootstrapRecordHash','Read-MIR4ArchiveBytes','Write-MIR4DeterministicRawTreeArchive')) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "[mir4-shadow-dependency] $name" }
  }
}

function Get-MIR4ShadowBaseline {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $path = Join-Path $RepoRoot 'spec/distribution/mir4-golden-four-target-baseline-v1.json'
  $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $record)) { throw '[mir4-shadow-baseline-self-hash]' }
  if ([string]$record.kind -cne 'MIR4GoldenFourTargetBaselineV1' -or
      [bool]$record.transition_gate.package_cutover -or
      -not [bool]$record.invariants.all_paths_classified) {
    throw '[mir4-shadow-baseline-boundary]'
  }
  return $record
}

function Get-MIR4ShadowTargetPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('f210','f200','f110','f100')][string]$Target
  )
  $repo = Get-MIR4ShadowRepoRoot -RepoRoot $RepoRoot
  Import-MIR4ShadowMaterializerDependencies -RepoRoot $repo
  $baseline = Get-MIR4ShadowBaseline -RepoRoot $repo
  $targetRows = @($baseline.targets | Where-Object { [string]$_.target -ceq $Target })
  if ($targetRows.Count -ne 1) { throw "[mir4-shadow-target-row] $Target" }
  $targetRow = $targetRows[0]
  $family = if ($Target -in @('f210','f200')) { 'modern' } else { 'legacy' }
  $familySource = if ($family -ceq 'modern') { 'f210' } else { 'f110' }
  $sourceRows = @{}
  foreach ($row in @($baseline.targets)) { $sourceRows[[string]$row.target] = $row }
  $layers = @(
    [pscustomobject][ordered]@{name='common';source_target='f210';entries=@($baseline.classification.common)}
    [pscustomobject][ordered]@{name="families.$family";source_target=$familySource;entries=@($baseline.classification.families.$family)}
    [pscustomobject][ordered]@{name="targets.$Target";source_target=$Target;entries=@($baseline.classification.targets.$Target)}
  )
  $pathMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($layer in $layers) {
    $source = $sourceRows[[string]$layer.source_target]
    foreach ($entry in @($layer.entries)) {
      $path = [string]$entry.path
      Assert-MIR4PortableArchivePath -Path $path
      if ($pathMap.ContainsKey($path)) { throw "[mir4-shadow-layer-overlap] $Target $path" }
      $pathMap.Add($path, [pscustomobject][ordered]@{
        path=$path
        bytes=[int64]$entry.bytes
        sha256=[string]$entry.sha256
        layer=[string]$layer.name
        source_target=[string]$layer.source_target
        source_archive=[string]$source.archive.path
      })
    }
  }
  $expectedRows = @($targetRow.entries | ForEach-Object { "$($_.path)|$($_.bytes)|$($_.sha256)" } | Sort-Object -CaseSensitive)
  $actualRows = @($pathMap.Values | ForEach-Object { "$($_.path)|$($_.bytes)|$($_.sha256)" } | Sort-Object -CaseSensitive)
  if (($expectedRows -join [string][char]10) -cne ($actualRows -join [string][char]10)) {
    throw "[mir4-shadow-plan-parity] $Target"
  }
  return [pscustomobject][ordered]@{
    baseline=$baseline
    target=$targetRow
    family=$family
    layers=$layers
    bindings=@($pathMap.Values | Sort-Object path -CaseSensitive)
  }
}

function Assert-MIR4ShadowInventoryParity {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$Expected,[Parameter(Mandatory)]$Actual,[Parameter(Mandatory)][string]$Target)
  if ([string]$Actual.root -cne [string]$Expected.archive.root -or
      [string]$Actual.content_sha256 -cne [string]$Expected.archive.content_sha256 -or
      [int]$Actual.entry_count -ne [int]$Expected.archive.entry_count) {
    throw "[mir4-shadow-inventory-identity] $Target"
  }
  $expectedRows = @($Expected.entries | ForEach-Object { "$($_.path)|$($_.bytes)|$($_.sha256)" } | Sort-Object -CaseSensitive)
  $actualRows = @($Actual.entries | ForEach-Object { "$($_.path)|$($_.raw_bytes)|$($_.raw_sha256)" } | Sort-Object -CaseSensitive)
  if (($expectedRows -join [string][char]10) -cne ($actualRows -join [string][char]10)) {
    throw "[mir4-shadow-inventory-entries] $Target"
  }
}

function New-MIR4ShadowTargetMaterialization {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('f210','f200','f110','f100')][string]$Target,
    [Parameter(Mandatory)][ValidatePattern('^[A-Z][A-Z0-9-]*$')][string]$Construction,
    [string]$OutputRoot='build/mir4/package-source/shadow-materializer-v1'
  )
  $repo = Get-MIR4ShadowRepoRoot -RepoRoot $RepoRoot
  Import-MIR4ShadowMaterializerDependencies -RepoRoot $repo
  if (-not [IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot = Join-Path $repo $OutputRoot }
  $output = [IO.Path]::GetFullPath($OutputRoot)
  if (-not (Test-Path -LiteralPath $output -PathType Container)) { New-Item -ItemType Directory -Force -Path $output | Out-Null }
  $plan = Get-MIR4ShadowTargetPlan -RepoRoot $repo -Target $Target
  $relativeConstruction = "$Target/$Construction"
  $constructionRoot = Resolve-MIR4ArtifactPath -OutputRoot $output -RelativePath $relativeConstruction
  Remove-MIR4BuildTree -OutputRoot $output -Path $constructionRoot
  $treeRoot = Join-Path $constructionRoot 'tree'
  New-Item -ItemType Directory -Force -Path $treeRoot | Out-Null
  foreach ($binding in @($plan.bindings)) {
    $sourcePath = Join-Path $repo ([string]$binding.source_archive)
    $bytes = Read-MIR4ArchiveBytes -Path $sourcePath -RelativePath ([string]$binding.path)
    if ([int64]$bytes.Length -ne [int64]$binding.bytes -or
        (Get-MIR4Sha256Bytes -Bytes $bytes) -cne [string]$binding.sha256) {
      throw "[mir4-shadow-source-byte-binding] $Target $($binding.path)"
    }
    $destination = Resolve-MIR4ArtifactPath -OutputRoot $treeRoot -RelativePath ([string]$binding.path)
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($destination, $bytes)
  }
  $archiveName = "more-infinite-research_$([string]$plan.target.distribution_version).zip"
  $archivePath = Join-Path $constructionRoot $archiveName
  Write-MIR4DeterministicRawTreeArchive -SourceRoot $treeRoot -EntryRoot ([string]$plan.target.archive.root) -OutputPath $archivePath -ContainmentRoot $output
  $inventory = Get-MIR4ArchiveInventory -Path $archivePath
  Assert-MIR4ShadowInventoryParity -Expected $plan.target -Actual $inventory -Target $Target
  return [pscustomobject][ordered]@{
    target=$Target
    construction=$Construction
    family=[string]$plan.family
    distribution_version=[string]$plan.target.distribution_version
    baseline_record_sha256=[string]$plan.baseline.record_sha256
    layer_counts=[pscustomobject][ordered]@{common=@($plan.layers[0].entries).Count;family=@($plan.layers[1].entries).Count;target=@($plan.layers[2].entries).Count}
    tree_path=$treeRoot
    archive_path=$archivePath
    archive_sha256=[string]$inventory.archive_sha256
    content_sha256=[string]$inventory.content_sha256
    entry_count=[int]$inventory.entry_count
    exact_tree_parity=$true
    historical_archive_byte_parity=([string]$inventory.archive_sha256 -ceq [string]$plan.target.archive.sha256)
  }
}

function Invoke-MIR4ShadowTargetParity {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [ValidateSet('f210','f200','f110','f100')][string[]]$Targets=@('f210','f200','f110','f100'),
    [string]$OutputRoot='build/mir4/package-source/shadow-materializer-v1',
    [string]$ReportPath='build/reports/package-source/mir4-shadow-target-materializer-v1.json'
  )
  $repo = Get-MIR4ShadowRepoRoot -RepoRoot $RepoRoot
  Import-MIR4ShadowMaterializerDependencies -RepoRoot $repo
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($target in $Targets) {
    $a = New-MIR4ShadowTargetMaterialization -RepoRoot $repo -Target $target -Construction 'A' -OutputRoot $OutputRoot
    $b = New-MIR4ShadowTargetMaterialization -RepoRoot $repo -Target $target -Construction 'B' -OutputRoot $OutputRoot
    if ([string]$a.archive_sha256 -cne [string]$b.archive_sha256 -or
        [string]$a.content_sha256 -cne [string]$b.content_sha256 -or
        [int]$a.entry_count -ne [int]$b.entry_count) {
      throw "[mir4-shadow-determinism] $target"
    }
    $rows.Add([pscustomobject][ordered]@{
      target=$target
      distribution_version=[string]$a.distribution_version
      family=[string]$a.family
      layer_counts=$a.layer_counts
      archive_a=[string]$a.archive_sha256
      archive_b=[string]$b.archive_sha256
      content_sha256=[string]$a.content_sha256
      entry_count=[int]$a.entry_count
      exact_tree_parity=$true
      deterministic_archive_bytes=$true
      historical_archive_byte_parity=([bool]$a.historical_archive_byte_parity -and [bool]$b.historical_archive_byte_parity)
    })
  }
  $baseline = Get-MIR4ShadowBaseline -RepoRoot $repo
  $report = [pscustomobject][ordered]@{
    schema=1
    kind='MIR4ShadowTargetMaterializerProofV1'
    status='passed-shadow-bootstrap-parity-no-cutover'
    baseline_record_sha256=[string]$baseline.record_sha256
    algorithm='golden-archive-byte-bootstrap-common-family-target-overlay-v1'
    targets=@($rows)
    invariants=[pscustomobject][ordered]@{exact_tree_parity=$true;deterministic_archive_bytes=$true;package_source_unchanged=$true;current_writer_unchanged=$true;runtime_replay_required_before_cutover=$true}
    transition_gate=[pscustomobject][ordered]@{source_move=$false;package_cutover=$false;old_writer_retirement=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
    record_sha256=''
  }
  $report.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $report
  if (-not [IO.Path]::IsPathRooted($ReportPath)) { $ReportPath = Join-Path $repo $ReportPath }
  $parent = Split-Path -Parent $ReportPath
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $json = ($report | ConvertTo-Json -Depth 100).Replace([Environment]::NewLine, [string][char]10) + [string][char]10
  [IO.File]::WriteAllText($ReportPath, $json, [Text.UTF8Encoding]::new($false))
  return $report
}
