Set-StrictMode -Version Latest

# This package-excluded module freezes the exact release-side byte set after a
# nine-target seal and protected-main promotion plan exist. It cannot sign,
# publish, change Git state, or turn a local copy into a public-release claim.
$mir42ReleaseAssetsRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42ReleaseAssetsRepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Get-MIR42ExactFourTargetCandidate -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42ReleaseAssetsRepoRoot 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
}
if (-not (Get-Command Get-MIR42NineTargetProtectedMainPromotionPlan -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42ReleaseAssetsRepoRoot 'tools/mir/application/release/readiness/MIR42ProtectedMainPromotion.ps1')
}
if (-not (Get-Command Assert-MIR42SupportCollectorBundle -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42ReleaseAssetsRepoRoot 'tools/mir/application/release/readiness/MIR42SupportCollectorBundle.ps1')
}

$script:MIR42ReleaseAssetTargets = @('f210', 'f200', 'f110', 'f100', 'f017', 'f016', 'f015', 'f014', 'f013')
$script:MIR42ReleaseAssetPublicSupportPaths = @(
  'SHA256SUMS.txt', 'SHA256SUMS.txt.sig', 'mir-4.2.0.qualification.json',
  'mir-4.2.0.provenance.json', 'mir-4.2.0.components.json', 'mir-4.2.0.release.json',
  'MIR42-Offline-Support-Collector.zip'
)
$script:MIR42ReleaseAssetLocalPaths = @('release-notes.md')

function Assert-MIR42ReleaseAssetProperties {
  param(
    [Parameter(Mandatory)]$Value,
    [Parameter(Mandatory)][string[]]$Expected,
    [Parameter(Mandatory)][string]$Code
  )
  if ($null -eq $Value -or (($Value.PSObject.Properties.Name | Sort-Object) -join '|') -cne (($Expected | Sort-Object) -join '|')) {
    throw "[$Code-shape]"
  }
}

function Get-MIR42ReleaseAssetFileMap {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Code)

  if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "[$Code-root-missing]" }
  $resolved = (Resolve-Path -LiteralPath $Root).Path
  $rootItem = Get-Item -LiteralPath $resolved -Force
  if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "[$Code-root-reparse]" }
  $files = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($item in @(Get-ChildItem -LiteralPath $resolved -File -Recurse -Force)) {
    try { $null = Assert-MIR4NoReparseAncestors -Root $resolved -Path $item.FullName }
    catch { throw "[$Code-reparse]" }
    $relative = [IO.Path]::GetRelativePath($resolved, $item.FullName).Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative -match '(^|/)\.{1,2}(/|$)' -or $relative.Contains(':')) {
      throw "[$Code-path]"
    }
    if (-not $files.TryAdd($relative, [pscustomobject][ordered]@{
      path = $relative
      full_path = $item.FullName
      sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
      bytes = [int64]$item.Length
    })) { throw "[$Code-duplicate-path] $relative" }
  }
  return [pscustomobject][ordered]@{root=$resolved;files=$files}
}

function Assert-MIR42ReleaseAssetBooleanFlags {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string[]]$Fields,[Parameter(Mandatory)][string]$Code)
  foreach ($field in $Fields) {
    $property = $Value.PSObject.Properties[$field]
    if ($null -eq $property -or $property.Value -isnot [bool]) { throw "[$Code-flag-type] $field" }
  }
}

function Get-MIR42ReleaseAssetFile {
  param([Parameter(Mandatory)]$Map,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  if (-not $Map.files.ContainsKey($Path)) { throw "[$Code-missing] $Path" }
  return $Map.files[$Path]
}

function Assert-MIR42ReleaseAssetExactFileSet {
  param([Parameter(Mandatory)]$Map,[Parameter(Mandatory)][string[]]$Expected,[Parameter(Mandatory)][string]$Code)
  if ($Map.files.Count -ne $Expected.Count) { throw "[$Code-count]" }
  foreach ($path in $Expected) {
    if (-not $Map.files.ContainsKey($path)) { throw "[$Code-missing] $path" }
  }
  foreach ($path in $Map.files.Keys) {
    if ($path -notin $Expected) { throw "[$Code-extra] $path" }
  }
}

function Get-MIR42ReleaseAssetSetSha256 {
  param([Parameter(Mandatory)][object[]]$Assets)
  $rows = @($Assets | ForEach-Object { "$( [string]$_.path )`t$( [int64]$_.bytes )`t$( [string]$_.sha256 )" })
  return Get-MIR4Sha256String -Value ($rows -join "`n")
}

function Assert-MIR42NineTargetReleaseAssetSeal {
  param([Parameter(Mandatory)]$Seal,[Parameter(Mandatory)]$Candidate)

  $contract = Get-MIR42SealScopeContract -Scope 'nine-target'
  $record = $Seal.record
  foreach ($field in @('schema','kind','status','source','candidate_manifest','targets','protected_main_promotion_authorized','human_go_required_after_main_readback','tagging_authorized','publication_authorized')) {
    if ($record.PSObject.Properties.Name -notcontains $field) { throw "[mir42-release-assets-seal-field] $field" }
  }
  Assert-MIR42ReleaseAssetBooleanFlags -Value $record -Fields @('protected_main_promotion_authorized','human_go_required_after_main_readback','tagging_authorized','publication_authorized') -Code 'mir42-release-assets-seal'
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne [string]$contract.seal_kind -or
      [string]$record.status -cne [string]$contract.seal_status -or
      [bool]$record.protected_main_promotion_authorized -or -not [bool]$record.human_go_required_after_main_readback -or
      [bool]$record.tagging_authorized -or [bool]$record.publication_authorized) {
    throw '[mir42-release-assets-seal-state]'
  }
  foreach ($field in @('commit','tree','package_source_sha256')) {
    if ([string]$record.source.$field -cne [string]$Candidate.source.$field) { throw "[mir42-release-assets-seal-source] $field" }
  }
  if ([string]$record.candidate_manifest.sha256 -cne [string]$Candidate.identity.sha256 -or
      [string]$record.candidate_manifest.record_sha256 -cne [string]$Candidate.identity.record.record_sha256) {
    throw '[mir42-release-assets-seal-candidate]'
  }
  Assert-MIR42SealTargetSet -Rows @($record.targets) -Scope 'nine-target' -Code 'mir42-release-assets-seal'
  for ($index = 0; $index -lt $script:MIR42ReleaseAssetTargets.Count; $index++) {
    $actual = $record.targets[$index]
    $expected = $Candidate.targets[$index]
    foreach ($field in @('target','distribution_version','archive_sha256','content_sha256','entry_count')) {
      if ([string]$actual.$field -cne [string]$expected.$field) { throw "[mir42-release-assets-seal-target] $([string]$expected.target)/$field" }
    }
  }
}

function Assert-MIR42NineTargetReleaseAssetPromotionPlan {
  param([Parameter(Mandatory)]$PromotionPlan,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Seal)

  foreach ($field in @('schema','kind','status','scope','source','technical_seal','candidate_manifest','target_assets','remote_mutation_performed','protected_main_promotion_authorized','human_go_required_after_main_readback','tagging_authorized','publication_authorized')) {
    if ($PromotionPlan.PSObject.Properties.Name -notcontains $field) { throw "[mir42-release-assets-promotion-field] $field" }
  }
  Assert-MIR42ReleaseAssetBooleanFlags -Value $PromotionPlan -Fields @('remote_mutation_performed','protected_main_promotion_authorized','human_go_required_after_main_readback','tagging_authorized','publication_authorized') -Code 'mir42-release-assets-promotion'
  if ([int]$PromotionPlan.schema -ne 1 -or [string]$PromotionPlan.kind -cne 'MIR42NineTargetProtectedMainPromotionPlanV1' -or
      [string]$PromotionPlan.status -cne 'MIR-4.2-NINE-TARGET-PROTECTED-MAIN-PROMOTION-PLAN-ONLY' -or
      [string]$PromotionPlan.scope -cne 'nine-target' -or [bool]$PromotionPlan.remote_mutation_performed -or
      [bool]$PromotionPlan.protected_main_promotion_authorized -or -not [bool]$PromotionPlan.human_go_required_after_main_readback -or
      [bool]$PromotionPlan.tagging_authorized -or [bool]$PromotionPlan.publication_authorized) {
    throw '[mir42-release-assets-promotion-state]'
  }
  foreach ($field in @('commit','tree','package_source_sha256')) {
    if ([string]$PromotionPlan.source.$field -cne [string]$Candidate.source.$field) { throw "[mir42-release-assets-promotion-source] $field" }
  }
  if ([string]$PromotionPlan.technical_seal.sha256 -cne [string]$Seal.sha256 -or
      [string]$PromotionPlan.technical_seal.record_sha256 -cne [string]$Seal.record.record_sha256 -or
      [string]$PromotionPlan.candidate_manifest.sha256 -cne [string]$Candidate.identity.sha256 -or
      [string]$PromotionPlan.candidate_manifest.record_sha256 -cne [string]$Candidate.identity.record.record_sha256) {
    throw '[mir42-release-assets-promotion-binding]'
  }
  Assert-MIR42SealTargetSet -Rows @($PromotionPlan.target_assets) -Scope 'nine-target' -Code 'mir42-release-assets-promotion'
  for ($index = 0; $index -lt $script:MIR42ReleaseAssetTargets.Count; $index++) {
    $actual = $PromotionPlan.target_assets[$index]
    $expected = $Candidate.targets[$index]
    foreach ($field in @('target','distribution_version','archive_sha256','content_sha256','entry_count')) {
      if ([string]$actual.$field -cne [string]$expected.$field) { throw "[mir42-release-assets-promotion-target] $([string]$expected.target)/$field" }
    }
  }
}

function Assert-MIR42ReleaseAssetSourceAndCandidate {
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][string]$Code)

  foreach ($field in @('commit','tree','package_source_sha256')) {
    if ([string]$Record.source.$field -cne [string]$Candidate.source.$field) { throw "[$Code-source] $field" }
  }
  if ([string]$Record.candidate_manifest.sha256 -cne [string]$Candidate.identity.sha256 -or
      [string]$Record.candidate_manifest.record_sha256 -cne [string]$Candidate.identity.record.record_sha256) {
    throw "[$Code-candidate]"
  }
}

function Assert-MIR42ReleaseAssetTargetBindings {
  param([Parameter(Mandatory)]$Rows,[Parameter(Mandatory)][object[]]$PackageAssets,[Parameter(Mandatory)][string]$Code)

  Assert-MIR42SealTargetSet -Rows @($Rows) -Scope 'nine-target' -Code $Code
  for ($index = 0; $index -lt $script:MIR42ReleaseAssetTargets.Count; $index++) {
    $actual = $Rows[$index]
    $expected = $PackageAssets[$index]
    foreach ($field in @('target','distribution_version','archive_sha256','content_sha256','entry_count')) {
      $actualValue = if ($field -eq 'archive_sha256') { [string]$actual.archive_sha256 } else { [string]$actual.$field }
      $expectedValue = if ($field -eq 'archive_sha256') { [string]$expected.sha256 } else { [string]$expected.$field }
      if ($actualValue -cne $expectedValue) { throw "[$Code-target] $([string]$expected.target)/$field" }
    }
  }
}

function Read-MIR42ReleaseAssetSupportingRecord {
  param(
    [Parameter(Mandatory)]$Asset,
    [Parameter(Mandatory)]$Candidate,
    [Parameter(Mandatory)]$Seal,
    [Parameter(Mandatory)][object[]]$PackageAssets,
    [Parameter(Mandatory)][ValidateSet('qualification','provenance','components','release-manifest')][string]$Role,
    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PreManifestGithubAssets,
    [Parameter(Mandatory)][object[]]$UploadTexts,
    [Parameter(Mandatory)]$Notes
  )

  $identity = Read-MIR42SealRecord -Path $Asset.full_path -Code ('mir42-release-assets-' + $Role)
  $record = $identity.record
  $base = @('schema','kind','status','release','source','candidate_manifest','human_go_required_after_main_readback','tagging_authorized','publication_authorized','record_sha256')
  $expected = switch ($Role) {
    'qualification' { $base + @('targets') }
    'provenance' { $base + @('package_source_sha256','outputs') }
    'components' { $base + @('player_assets') }
    'release-manifest' { $base + @('technical_seal','github_assets','manifest_asset','release_body','mod_portal_upload_texts','signature_verified') }
  }
  Assert-MIR42ReleaseAssetProperties -Value $record -Expected $expected -Code ('mir42-release-assets-' + $Role)
  $booleanFields = @('human_go_required_after_main_readback','tagging_authorized','publication_authorized')
  if ($Role -ceq 'release-manifest') { $booleanFields += 'signature_verified' }
  Assert-MIR42ReleaseAssetBooleanFlags -Value $record -Fields $booleanFields -Code ('mir42-release-assets-' + $Role)
  $kind = switch ($Role) {
    'qualification' { 'MIR42NineTargetReleaseQualificationSummaryV1' }
    'provenance' { 'MIR42NineTargetReleaseProvenanceV1' }
    'components' { 'MIR42NineTargetComponentInventoryV1' }
    'release-manifest' { 'MIR42NineTargetReleaseManifestV1' }
  }
  $status = switch ($Role) {
    'qualification' { 'MIR-4.2-NINE-TARGET-TECHNICALLY-QUALIFIED-NONPUBLIC' }
    'provenance' { 'MIR-4.2-NINE-TARGET-PROVENANCE-FROZEN-NONPUBLIC' }
    'components' { 'MIR-4.2-NINE-TARGET-COMPONENTS-FROZEN-NONPUBLIC' }
    'release-manifest' { 'MIR-4.2-NINE-TARGET-RELEASE-MANIFEST-FROZEN-NONPUBLIC' }
  }
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne $kind -or [string]$record.status -cne $status -or
      -not [bool]$record.human_go_required_after_main_readback -or [bool]$record.tagging_authorized -or [bool]$record.publication_authorized) {
    throw "[mir42-release-assets-$Role-state]"
  }
  Assert-MIR42ReleaseAssetProperties -Value $record.release -Expected @('source_version','tag') -Code ('mir42-release-assets-' + $Role + '-release')
  if ([string]$record.release.source_version -cne '4.2.0' -or [string]$record.release.tag -cne 'v4.2.0') { throw "[mir42-release-assets-$Role-release]" }
  Assert-MIR42ReleaseAssetSourceAndCandidate -Record $record -Candidate $Candidate -Code ('mir42-release-assets-' + $Role)
  switch ($Role) {
    'qualification' { Assert-MIR42ReleaseAssetTargetBindings -Rows @($record.targets) -PackageAssets $PackageAssets -Code 'mir42-release-assets-qualification' }
    'provenance' {
      if ([string]$record.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256) { throw '[mir42-release-assets-provenance-package-source]' }
      Assert-MIR42ReleaseAssetTargetBindings -Rows @($record.outputs) -PackageAssets $PackageAssets -Code 'mir42-release-assets-provenance'
    }
    'components' { Assert-MIR42ReleaseAssetTargetBindings -Rows @($record.player_assets) -PackageAssets $PackageAssets -Code 'mir42-release-assets-components' }
    'release-manifest' {
      if ([string]$record.technical_seal.sha256 -cne [string]$Seal.sha256 -or [string]$record.technical_seal.record_sha256 -cne [string]$Seal.record.record_sha256 -or
          [string]$record.manifest_asset.name -cne 'mir-4.2.0.release.json' -or [string]$record.release_body.path -cne 'release-notes.md' -or
          [string]$record.release_body.sha256 -cne [string]$Notes.sha256 -or [int64]$record.release_body.bytes -ne [int64]$Notes.bytes -or
          [bool]$record.signature_verified) { throw '[mir42-release-assets-release-manifest-binding]' }
      if (@($record.github_assets).Count -ne $PreManifestGithubAssets.Count -or @($record.mod_portal_upload_texts).Count -ne $UploadTexts.Count) { throw '[mir42-release-assets-release-manifest-count]' }
      for ($index = 0; $index -lt $PreManifestGithubAssets.Count; $index++) {
        $actual = $record.github_assets[$index]; $expectedAsset = $PreManifestGithubAssets[$index]
        Assert-MIR42ReleaseAssetProperties -Value $actual -Expected @('name','role','target','sha256','bytes') -Code 'mir42-release-assets-release-manifest-github'
        if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $actual) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $expectedAsset)) { throw "[mir42-release-assets-release-manifest-github] $index" }
      }
      for ($index = 0; $index -lt $UploadTexts.Count; $index++) {
        $actual = $record.mod_portal_upload_texts[$index]; $expectedUpload = $UploadTexts[$index]
        Assert-MIR42ReleaseAssetProperties -Value $actual -Expected @('target','path','sha256','bytes') -Code 'mir42-release-assets-release-manifest-upload'
        if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $actual) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $expectedUpload)) { throw "[mir42-release-assets-release-manifest-upload] $index" }
      }
    }
  }
  return [pscustomobject][ordered]@{role=$Role;path=[string]$Asset.path;sha256=[string]$Asset.sha256;bytes=[int64]$Asset.bytes;record_sha256=[string]$record.record_sha256}
}

function Write-MIR42ReleaseAssetInventoryRecord {
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$OutputPath)

  $output = [IO.Path]::GetFullPath($OutputPath)
  $parent = Split-Path -Parent $output
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $normalized = (ConvertTo-MIR4BootstrapCanonicalJson -Value $Record | ConvertFrom-Json -Depth 100 -DateKind String)
  $normalized.record_sha256 = ''
  $normalized.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $normalized
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4BootstrapCanonicalJson -Value $normalized) + "`n")
  if (Test-Path -LiteralPath $output -PathType Leaf) {
    $existing = [IO.File]::ReadAllBytes($output)
    if ([Convert]::ToHexString($existing) -ne [Convert]::ToHexString($bytes)) {
      throw '[mir42-release-assets-output-existing-authority-preserved]'
    }
  } else {
    try {
      $stream = [IO.File]::Open($output, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
      try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    } catch [IO.IOException] {
      if (-not (Test-Path -LiteralPath $output -PathType Leaf) -or
          [Convert]::ToHexString([IO.File]::ReadAllBytes($output)) -ne [Convert]::ToHexString($bytes)) {
        throw '[mir42-release-assets-output-race]'
      }
    }
  }
  return Read-MIR42SealRecord -Path $output -Code 'mir42-release-assets-output'
}

function Get-MIR42NineTargetReleaseAssetInventory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$TechnicalSealPath,
    [Parameter(Mandatory)]$PromotionPlan,
    [Parameter(Mandatory)][ValidatePattern('^4\.2\.0$')][string]$SourceVersion,
    [Parameter(Mandatory)][ValidatePattern('^v4\.2\.0$')][string]$ReleaseTag,
    [Parameter(Mandatory)][string]$AssetRoot,
    [Parameter(Mandatory)][string]$OutputPath
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $candidate = Get-MIR42ExactFourTargetCandidate -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath
  if ([string]$candidate.scope -cne 'nine-target') { throw '[mir42-release-assets-candidate-scope]' }
  Assert-MIR42SealTargetSet -Rows @($candidate.targets) -Scope 'nine-target' -Code 'mir42-release-assets-candidate'
  $seal = Read-MIR42SealRecord -Path $TechnicalSealPath -Code 'mir42-release-assets-seal'
  Assert-MIR42NineTargetReleaseAssetSeal -Seal $seal -Candidate $candidate
  Assert-MIR42NineTargetReleaseAssetPromotionPlan -PromotionPlan $PromotionPlan -Candidate $candidate -Seal $seal

  $assetMap = Get-MIR42ReleaseAssetFileMap -Root $AssetRoot -Code 'mir42-release-assets'
  $output = [IO.Path]::GetFullPath($OutputPath)
  $rootBoundary = $assetMap.root.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
  if ($output.StartsWith($rootBoundary, [StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-release-assets-output-under-asset-root]' }

  $expectedPaths = [Collections.Generic.List[string]]::new()
  $packageAssets = [Collections.Generic.List[object]]::new()
  foreach ($target in @($candidate.targets)) {
    $archiveName = [IO.Path]::GetFileName([string]$target.archive_path)
    if ([string]::IsNullOrWhiteSpace($archiveName) -or $archiveName -cne [string]$target.archive_path.Split([IO.Path]::DirectorySeparatorChar)[-1] -or
        [IO.Path]::GetExtension($archiveName) -cne '.zip') { throw "[mir42-release-assets-package-name] $([string]$target.target)" }
    $relative = 'assets/' + [string]$target.target + '/' + $archiveName
    $expectedPaths.Add($relative)
    $asset = Get-MIR42ReleaseAssetFile -Map $assetMap -Path $relative -Code 'mir42-release-assets-package'
    try { $archive = Get-MIR4ArchiveInventory -Path $asset.full_path }
    catch { throw "[mir42-release-assets-package-archive] $([string]$target.target)" }
    if ([string]$asset.sha256 -cne [string]$target.archive_sha256 -or [int64]$asset.bytes -ne [int64]$archive.bytes -or
        [string]$archive.archive_sha256 -cne [string]$target.archive_sha256 -or [string]$archive.content_sha256 -cne [string]$target.content_sha256 -or
        [int]$archive.entry_count -ne [int]$target.entry_count) {
      throw "[mir42-release-assets-package-identity] $([string]$target.target)"
    }
    $packageAssets.Add([pscustomobject][ordered]@{
      target = [string]$target.target
      distribution_version = [string]$target.distribution_version
      path = $relative
      public_name = $archiveName
      sha256 = [string]$asset.sha256
      bytes = [int64]$asset.bytes
      content_sha256 = [string]$archive.content_sha256
      entry_count = [int]$archive.entry_count
    })
  }
  foreach ($path in $script:MIR42ReleaseAssetPublicSupportPaths) { $expectedPaths.Add($path) }
  foreach ($path in $script:MIR42ReleaseAssetLocalPaths) { $expectedPaths.Add($path) }
  foreach ($target in $script:MIR42ReleaseAssetTargets) { $expectedPaths.Add(('upload-text/' + $target + '.md')) }
  Assert-MIR42ReleaseAssetExactFileSet -Map $assetMap -Expected @($expectedPaths) -Code 'mir42-release-assets'

  $checksum = Get-MIR42ReleaseAssetFile -Map $assetMap -Path 'SHA256SUMS.txt' -Code 'mir42-release-assets-checksum'
  $expectedChecksum = (@($packageAssets | ForEach-Object { "$([string]$_.sha256)  $([string]$_.public_name)" }) -join "`n") + "`n"
  $expectedChecksumSha256 = Get-MIR4Sha256String -Value $expectedChecksum
  $expectedChecksumBytes = [Text.UTF8Encoding]::new($false).GetByteCount($expectedChecksum)
  if ([int64]$checksum.bytes -ne [int64]$expectedChecksumBytes -or [string]$checksum.sha256 -cne $expectedChecksumSha256) {
    throw '[mir42-release-assets-checksum-content]'
  }
  $signature = Get-MIR42ReleaseAssetFile -Map $assetMap -Path 'SHA256SUMS.txt.sig' -Code 'mir42-release-assets-signature'
  $notes = Get-MIR42ReleaseAssetFile -Map $assetMap -Path 'release-notes.md' -Code 'mir42-release-assets-notes'
  $collectorFile = Get-MIR42ReleaseAssetFile -Map $assetMap -Path $script:MIR42SupportCollectorAssetName -Code 'mir42-release-assets-collector'
  $collector = Assert-MIR42SupportCollectorBundle -RepoRoot $RepoRoot -SourceCommit ([string]$candidate.source.commit) -Path $collectorFile.full_path
  if ([string]$collector.sha256 -cne [string]$collectorFile.sha256 -or [int64]$collector.bytes -ne [int64]$collectorFile.bytes) {
    throw '[mir42-release-assets-collector-identity]'
  }
  if ([int64]$signature.bytes -le 0 -or [int64]$notes.bytes -le 0) { throw '[mir42-release-assets-support-empty]' }
  $uploadTexts = @(
    foreach ($target in $script:MIR42ReleaseAssetTargets) {
      $upload = Get-MIR42ReleaseAssetFile -Map $assetMap -Path ('upload-text/' + $target + '.md') -Code 'mir42-release-assets-upload-text'
      if ([int64]$upload.bytes -le 0) { throw "[mir42-release-assets-upload-text-empty] $target" }
      [pscustomobject][ordered]@{target=$target;path=[string]$upload.path;sha256=[string]$upload.sha256;bytes=[int64]$upload.bytes}
    }
  )

  $preManifestGithubAssets = [Collections.Generic.List[object]]::new()
  foreach ($asset in $packageAssets) {
    $preManifestGithubAssets.Add([pscustomobject][ordered]@{name=[string]$asset.public_name;role='package';target=[string]$asset.target;sha256=[string]$asset.sha256;bytes=[int64]$asset.bytes})
  }
  foreach ($support in @(
    [pscustomobject][ordered]@{name='SHA256SUMS.txt';role='checksum';target='';sha256=[string]$checksum.sha256;bytes=[int64]$checksum.bytes},
    [pscustomobject][ordered]@{name='SHA256SUMS.txt.sig';role='signature';target='';sha256=[string]$signature.sha256;bytes=[int64]$signature.bytes},
    [pscustomobject][ordered]@{name=$script:MIR42SupportCollectorAssetName;role='support-collector';target='';sha256=[string]$collector.sha256;bytes=[int64]$collector.bytes}
  )) { $preManifestGithubAssets.Add($support) }
  $qualificationAsset = Get-MIR42ReleaseAssetFile -Map $assetMap -Path 'mir-4.2.0.qualification.json' -Code 'mir42-release-assets-qualification'
  $provenanceAsset = Get-MIR42ReleaseAssetFile -Map $assetMap -Path 'mir-4.2.0.provenance.json' -Code 'mir42-release-assets-provenance'
  $componentsAsset = Get-MIR42ReleaseAssetFile -Map $assetMap -Path 'mir-4.2.0.components.json' -Code 'mir42-release-assets-components'
  $releaseManifestAsset = Get-MIR42ReleaseAssetFile -Map $assetMap -Path 'mir-4.2.0.release.json' -Code 'mir42-release-assets-release-manifest'
  $qualification = Read-MIR42ReleaseAssetSupportingRecord -Asset $qualificationAsset -Candidate $candidate -Seal $seal -PackageAssets @($packageAssets) -Role qualification -PreManifestGithubAssets @() -UploadTexts @($uploadTexts) -Notes $notes
  $provenance = Read-MIR42ReleaseAssetSupportingRecord -Asset $provenanceAsset -Candidate $candidate -Seal $seal -PackageAssets @($packageAssets) -Role provenance -PreManifestGithubAssets @() -UploadTexts @($uploadTexts) -Notes $notes
  $components = Read-MIR42ReleaseAssetSupportingRecord -Asset $componentsAsset -Candidate $candidate -Seal $seal -PackageAssets @($packageAssets) -Role components -PreManifestGithubAssets @() -UploadTexts @($uploadTexts) -Notes $notes
  foreach ($support in @(
    [pscustomobject][ordered]@{name='mir-4.2.0.qualification.json';role='qualification';target='';sha256=[string]$qualification.sha256;bytes=[int64]$qualification.bytes},
    [pscustomobject][ordered]@{name='mir-4.2.0.provenance.json';role='provenance';target='';sha256=[string]$provenance.sha256;bytes=[int64]$provenance.bytes},
    [pscustomobject][ordered]@{name='mir-4.2.0.components.json';role='components';target='';sha256=[string]$components.sha256;bytes=[int64]$components.bytes}
  )) { $preManifestGithubAssets.Add($support) }
  $releaseManifest = Read-MIR42ReleaseAssetSupportingRecord -Asset $releaseManifestAsset -Candidate $candidate -Seal $seal -PackageAssets @($packageAssets) -Role 'release-manifest' -PreManifestGithubAssets @($preManifestGithubAssets) -UploadTexts @($uploadTexts) -Notes $notes
  $githubAssets = [Collections.Generic.List[object]]::new()
  foreach ($asset in $preManifestGithubAssets) { $githubAssets.Add($asset) }
  $githubAssets.Add([pscustomobject][ordered]@{name='mir-4.2.0.release.json';role='release-manifest';target='';sha256=[string]$releaseManifest.sha256;bytes=[int64]$releaseManifest.bytes})
  $names = @($githubAssets | ForEach-Object { [string]$_.name })
  if (@($names | Sort-Object -Unique).Count -ne $names.Count) { throw '[mir42-release-assets-public-name-collision]' }

  $allAssets = @($packageAssets) + @([pscustomobject][ordered]@{path=[string]$checksum.path;sha256=[string]$checksum.sha256;bytes=[int64]$checksum.bytes}) +
    @([pscustomobject][ordered]@{path=[string]$signature.path;sha256=[string]$signature.sha256;bytes=[int64]$signature.bytes}) + @($collector) +
    @($qualification) + @($provenance) + @($components) + @($releaseManifest) +
    @([pscustomobject][ordered]@{path=[string]$notes.path;sha256=[string]$notes.sha256;bytes=[int64]$notes.bytes}) + @($uploadTexts)
  $inventory = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42NineTargetReleaseAssetInventoryV1'
    status = 'MIR-4.2-NINE-TARGET-RELEASE-ASSETS-FROZEN-NONPUBLIC'
    release = [ordered]@{source_version=$SourceVersion;tag=$ReleaseTag}
    source = [ordered]@{commit=[string]$candidate.source.commit;tree=[string]$candidate.source.tree;package_source_sha256=[string]$candidate.source.package_source_sha256}
    candidate_manifest = [ordered]@{sha256=[string]$candidate.identity.sha256;record_sha256=[string]$candidate.identity.record.record_sha256}
    technical_seal = [ordered]@{sha256=[string]$seal.sha256;record_sha256=[string]$seal.record.record_sha256}
    promotion_plan = [ordered]@{kind=[string]$PromotionPlan.kind;status=[string]$PromotionPlan.status;main_before=[string]$PromotionPlan.main_before;source_commit=[string]$PromotionPlan.source.commit;source_tree=[string]$PromotionPlan.source.tree;candidate_manifest_sha256=[string]$PromotionPlan.candidate_manifest.sha256;technical_seal_sha256=[string]$PromotionPlan.technical_seal.sha256}
    package_assets = @($packageAssets)
    github_assets = @($githubAssets)
    checksum = [ordered]@{path=[string]$checksum.path;sha256=[string]$checksum.sha256;bytes=[int64]$checksum.bytes}
    signature = [ordered]@{path=[string]$signature.path;sha256=[string]$signature.sha256;bytes=[int64]$signature.bytes;signature_verified=$false}
    qualification = $qualification
    provenance = $provenance
    components = $components
    release_manifest = $releaseManifest
    release_notes = [ordered]@{path=[string]$notes.path;sha256=[string]$notes.sha256;bytes=[int64]$notes.bytes}
    mod_portal_upload_texts = @($uploadTexts)
    asset_root_file_set_sha256 = Get-MIR42ReleaseAssetSetSha256 -Assets $allAssets
    protected_main_promotion_authorized = $false
    human_go_required_after_main_readback = $true
    tagging_authorized = $false
    publication_authorized = $false
    public_readback_verified = $false
    record_sha256 = ''
  }
  return Write-MIR42ReleaseAssetInventoryRecord -Record $inventory -OutputPath $output
}

function Assert-MIR42NineTargetFrozenReleaseAssetInventory {
  param([Parameter(Mandatory)]$Record)

  Assert-MIR42ReleaseAssetProperties -Value $Record -Expected @('schema','kind','status','release','source','candidate_manifest','technical_seal','promotion_plan','package_assets','github_assets','checksum','signature','qualification','provenance','components','release_manifest','release_notes','mod_portal_upload_texts','asset_root_file_set_sha256','protected_main_promotion_authorized','human_go_required_after_main_readback','tagging_authorized','publication_authorized','public_readback_verified','record_sha256') -Code 'mir42-release-assets-inventory'
  Assert-MIR42ReleaseAssetBooleanFlags -Value $Record -Fields @('protected_main_promotion_authorized','human_go_required_after_main_readback','tagging_authorized','publication_authorized','public_readback_verified') -Code 'mir42-release-assets-inventory'
  Assert-MIR42ReleaseAssetBooleanFlags -Value $Record.signature -Fields @('signature_verified') -Code 'mir42-release-assets-inventory-signature'
  if ([int]$Record.schema -ne 1 -or [string]$Record.kind -cne 'MIR42NineTargetReleaseAssetInventoryV1' -or
      [string]$Record.status -cne 'MIR-4.2-NINE-TARGET-RELEASE-ASSETS-FROZEN-NONPUBLIC' -or
      [bool]$Record.protected_main_promotion_authorized -or -not [bool]$Record.human_go_required_after_main_readback -or
      [bool]$Record.tagging_authorized -or [bool]$Record.publication_authorized -or [bool]$Record.public_readback_verified) {
    throw '[mir42-release-assets-inventory-state]'
  }
  foreach ($field in @('commit','tree','package_source_sha256')) {
    if ([string]$Record.source.$field -notmatch '^[A-Fa-f0-9]{40,64}$') { throw "[mir42-release-assets-inventory-source] $field" }
  }
  Assert-MIR42ReleaseAssetProperties -Value $Record.release -Expected @('source_version','tag') -Code 'mir42-release-assets-inventory-release'
  if ([string]$Record.release.source_version -cne '4.2.0' -or [string]$Record.release.tag -cne 'v4.2.0') { throw '[mir42-release-assets-inventory-release-binding]' }
  Assert-MIR42ReleaseAssetProperties -Value $Record.candidate_manifest -Expected @('sha256','record_sha256') -Code 'mir42-release-assets-inventory-candidate'
  Assert-MIR42ReleaseAssetProperties -Value $Record.technical_seal -Expected @('sha256','record_sha256') -Code 'mir42-release-assets-inventory-seal'
  foreach ($hash in @([string]$Record.candidate_manifest.sha256,[string]$Record.candidate_manifest.record_sha256,[string]$Record.technical_seal.sha256,[string]$Record.technical_seal.record_sha256)) {
    if ($hash -notmatch '^[A-F0-9]{64}$') { throw '[mir42-release-assets-inventory-binding]' }
  }
  Assert-MIR42ReleaseAssetProperties -Value $Record.promotion_plan -Expected @('kind','status','main_before','source_commit','source_tree','candidate_manifest_sha256','technical_seal_sha256') -Code 'mir42-release-assets-inventory-promotion'
  if ([string]$Record.promotion_plan.kind -cne 'MIR42NineTargetProtectedMainPromotionPlanV1' -or
      [string]$Record.promotion_plan.status -cne 'MIR-4.2-NINE-TARGET-PROTECTED-MAIN-PROMOTION-PLAN-ONLY' -or
      [string]$Record.promotion_plan.source_commit -cne [string]$Record.source.commit -or [string]$Record.promotion_plan.source_tree -cne [string]$Record.source.tree -or
      [string]$Record.promotion_plan.candidate_manifest_sha256 -cne [string]$Record.candidate_manifest.sha256 -or
      [string]$Record.promotion_plan.technical_seal_sha256 -cne [string]$Record.technical_seal.sha256) {
    throw '[mir42-release-assets-inventory-promotion-binding]'
  }
  Assert-MIR42SealTargetSet -Rows @($Record.package_assets) -Scope 'nine-target' -Code 'mir42-release-assets-inventory-package'
  Assert-MIR42SealTargetSet -Rows @($Record.mod_portal_upload_texts) -Scope 'nine-target' -Code 'mir42-release-assets-inventory-upload-text'
  $public = @($Record.github_assets)
  if ($public.Count -ne 16) { throw '[mir42-release-assets-inventory-github-count]' }
  $expectedNames = [Collections.Generic.List[string]]::new()
  for ($index = 0; $index -lt $script:MIR42ReleaseAssetTargets.Count; $index++) {
    $package = $Record.package_assets[$index]
    Assert-MIR42ReleaseAssetProperties -Value $package -Expected @('target','distribution_version','path','public_name','sha256','bytes','content_sha256','entry_count') -Code 'mir42-release-assets-inventory-package'
    $expectedTarget = $script:MIR42ReleaseAssetTargets[$index]
    if ([string]$package.target -cne $expectedTarget -or [string]$package.path -cne ('assets/' + $expectedTarget + '/' + [string]$package.public_name) -or
        [string]$package.public_name -notmatch '\.zip$' -or [string]$package.sha256 -notmatch '^[A-F0-9]{64}$' -or [int64]$package.bytes -le 0 -or
        [string]$package.content_sha256 -notmatch '^[A-F0-9]{64}$' -or [int]$package.entry_count -le 0) { throw "[mir42-release-assets-inventory-package-binding] $expectedTarget" }
    $publicPackage = $public[$index]
    Assert-MIR42ReleaseAssetProperties -Value $publicPackage -Expected @('name','role','target','sha256','bytes') -Code 'mir42-release-assets-inventory-github'
    if ([string]$publicPackage.name -cne [string]$package.public_name -or [string]$publicPackage.role -cne 'package' -or [string]$publicPackage.target -cne $expectedTarget -or
        [string]$publicPackage.sha256 -cne [string]$package.sha256 -or [int64]$publicPackage.bytes -ne [int64]$package.bytes) { throw "[mir42-release-assets-inventory-github-package] $expectedTarget" }
    $expectedNames.Add([string]$package.public_name)
  }
  $support = @(
    @('SHA256SUMS.txt','checksum',$Record.checksum),
    @('SHA256SUMS.txt.sig','signature',$Record.signature),
    @($script:MIR42SupportCollectorAssetName,'support-collector',$public[11]),
    @('mir-4.2.0.qualification.json','qualification',$Record.qualification),
    @('mir-4.2.0.provenance.json','provenance',$Record.provenance),
    @('mir-4.2.0.components.json','components',$Record.components),
    @('mir-4.2.0.release.json','release-manifest',$Record.release_manifest)
  )
  for ($index = 0; $index -lt $support.Count; $index++) {
    $publicAsset = $public[$script:MIR42ReleaseAssetTargets.Count + $index]
    $name = [string]$support[$index][0]; $role = [string]$support[$index][1]; $asset = $support[$index][2]
    if ([string]$publicAsset.name -cne $name -or [string]$publicAsset.role -cne $role -or -not [string]::IsNullOrEmpty([string]$publicAsset.target) -or
        [string]$publicAsset.sha256 -cne [string]$asset.sha256 -or [string]$publicAsset.sha256 -cnotmatch '^[A-F0-9]{64}$' -or
        [int64]$publicAsset.bytes -ne [int64]$asset.bytes -or [int64]$publicAsset.bytes -le 0) { throw "[mir42-release-assets-inventory-github-support] $name" }
    $expectedNames.Add($name)
  }
  if (@($expectedNames | Sort-Object -Unique).Count -ne $expectedNames.Count) { throw '[mir42-release-assets-inventory-github-name-collision]' }
  Assert-MIR42ReleaseAssetProperties -Value $Record.checksum -Expected @('path','sha256','bytes') -Code 'mir42-release-assets-inventory-checksum'
  Assert-MIR42ReleaseAssetProperties -Value $Record.signature -Expected @('path','sha256','bytes','signature_verified') -Code 'mir42-release-assets-inventory-signature'
  foreach ($document in @(
    @('qualification','mir-4.2.0.qualification.json',$Record.qualification),
    @('provenance','mir-4.2.0.provenance.json',$Record.provenance),
    @('components','mir-4.2.0.components.json',$Record.components),
    @('release-manifest','mir-4.2.0.release.json',$Record.release_manifest)
  )) {
    $role = [string]$document[0]; $path = [string]$document[1]; $value = $document[2]
    Assert-MIR42ReleaseAssetProperties -Value $value -Expected @('role','path','sha256','bytes','record_sha256') -Code 'mir42-release-assets-inventory-document'
    if ([string]$value.role -cne $role -or [string]$value.path -cne $path -or [string]$value.sha256 -notmatch '^[A-F0-9]{64}$' -or
        [string]$value.record_sha256 -notmatch '^[A-F0-9]{64}$' -or [int64]$value.bytes -le 0) { throw "[mir42-release-assets-inventory-document] $role" }
  }
  Assert-MIR42ReleaseAssetProperties -Value $Record.release_notes -Expected @('path','sha256','bytes') -Code 'mir42-release-assets-inventory-notes'
  if ([string]$Record.checksum.path -cne 'SHA256SUMS.txt' -or [string]$Record.signature.path -cne 'SHA256SUMS.txt.sig' -or
      [string]$Record.release_notes.path -cne 'release-notes.md' -or [bool]$Record.signature.signature_verified -or
      [int64]$Record.checksum.bytes -le 0 -or [int64]$Record.signature.bytes -le 0 -or [int64]$Record.release_notes.bytes -le 0) {
    throw '[mir42-release-assets-inventory-support-binding]'
  }
  $collectorAsset = [pscustomobject][ordered]@{path=$script:MIR42SupportCollectorAssetName;sha256=[string]$public[11].sha256;bytes=[int64]$public[11].bytes}
  $allAssets = @($Record.package_assets) + @($Record.checksum) + @($Record.signature) + @($collectorAsset) + @($Record.qualification) + @($Record.provenance) + @($Record.components) + @($Record.release_manifest) + @($Record.release_notes) + @($Record.mod_portal_upload_texts)
  if ([string]$Record.asset_root_file_set_sha256 -cne (Get-MIR42ReleaseAssetSetSha256 -Assets $allAssets)) { throw '[mir42-release-assets-inventory-file-set]' }
}

function Read-MIR42NineTargetReleaseAssetInventory {
  param([Parameter(Mandatory)][string]$Path)
  $identity = Read-MIR42SealRecord -Path $Path -Code 'mir42-release-assets-inventory'
  Assert-MIR42NineTargetFrozenReleaseAssetInventory -Record $identity.record
  return $identity
}

function Read-MIR42NineTargetWrittenReleaseAuthorization {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path)

  $authorizationPath = (Resolve-Path -LiteralPath $Path).Path
  $schemaPath = Join-Path $mir42ReleaseAssetsRepoRoot 'spec/schemas/mir42-maintainer-written-release-authorization-v1.schema.json'
  if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { throw '[mir42-release-go-schema-missing]' }
  $schemaValid = $false
  try {
    $schemaValid = [bool](Get-Content -Raw -LiteralPath $authorizationPath | Test-Json -SchemaFile $schemaPath)
  } catch {
    throw '[mir42-release-go-schema]'
  }
  if (-not $schemaValid) {
    throw '[mir42-release-go-schema]'
  }
  $identity = Read-MIR42SealRecord -Path $authorizationPath -Code 'mir42-release-go'
  $record = $identity.record
  Assert-MIR42ReleaseAssetProperties -Value $record -Expected @(
    'schema','kind','status','recorded_from_user_turn_date','timezone','release','written_authorizations','maintainer_decisions',
    'nonnegotiable_constraints','current_controller_state','required_external_inputs_before_technical_seal','known_operator_inputs',
    'final_byte_binding','secret_values_present','warning','record_sha256'
  ) -Code 'mir42-release-go-shape'
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42MaintainerWrittenReleaseAuthorizationHandoffV1' -or
      [string]$record.status -cne 'written-maintainer-authorization-recorded-awaiting-exact-candidate-and-technical-proof' -or
      [string]$record.recorded_from_user_turn_date -notmatch '^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' -or
      [string]::IsNullOrWhiteSpace([string]$record.timezone) -or [bool]$record.secret_values_present) {
    throw '[mir42-release-go-state]'
  }
  Assert-MIR42ReleaseAssetProperties -Value $record.release -Expected @('source_version','tag','selected_targets') -Code 'mir42-release-go-release-shape'
  if ([string]$record.release.source_version -cne '4.2.0' -or [string]$record.release.tag -cne 'v4.2.0') { throw '[mir42-release-go-release]' }
  Assert-MIR42SealTargetSet -Rows @($record.release.selected_targets | ForEach-Object { [pscustomobject]@{ target = [string]$_ } }) -Scope 'nine-target' -Code 'mir42-release-go-targets'
  Assert-MIR42ReleaseAssetProperties -Value $record.written_authorizations -Expected @('complete_mir_4_2','protected_main_promotion','required_distribution_tags','github_publication','nine_target_github_zip_assets','mod_portal_upload') -Code 'mir42-release-go-authorizations-shape'
  $authorizationStates = [ordered]@{
    complete_mir_4_2 = 'authorized-subject-to-required-technical-checks'
    protected_main_promotion = 'authorized-after-accepted-technical-seal-and-governed-restore'
    required_distribution_tags = 'authorized-after-protected-main-readback-and-candidate-bound-go'
    github_publication = 'authorized-after-final-byte-acceptance-and-tag-verification'
    nine_target_github_zip_assets = 'authorized-after-final-byte-acceptance'
    # The written GO is for GitHub release assets.  Portal disposition remains
    # under its separately governed operator record.
    mod_portal_upload = 'not-claimed-by-this-github-release-authorization'
  }
  foreach ($field in $authorizationStates.Keys) {
    if ([string]$record.written_authorizations.$field -cne [string]$authorizationStates[$field]) { throw "[mir42-release-go-authorization] $field" }
  }
  Assert-MIR42ReleaseAssetProperties -Value $record.maintainer_decisions -Expected @('current_balance_direction','current_visual_direction','disclosed_limitations','additional_playtest_prompt','experimental_f210','f210_f200_playtest_receipt','technical_acceptance','candidate_binding','final_byte_hashes') -Code 'mir42-release-go-decision-shape'
  $decisionStates = [ordered]@{
    current_balance_direction = 'accepted'; current_visual_direction = 'accepted'; disclosed_limitations = 'accepted'
    additional_playtest_prompt = 'waived-for-this-release-decision'; experimental_f210 = 'qualified-experimental-consent-recorded'
    f210_f200_playtest_receipt = 'not-claimed-and-not-materialized'; technical_acceptance = 'not-established'
    candidate_binding = 'deferred-until-one-exact-accepted-candidate'; final_byte_hashes = 'not-yet-available'
  }
  foreach ($field in $decisionStates.Keys) {
    if ([string]$record.maintainer_decisions.$field -cne [string]$decisionStates[$field]) { throw "[mir42-release-go-decision] $field" }
  }
  Assert-MIR42ReleaseAssetProperties -Value $record.current_controller_state -Expected @('programme_path','programme_status','source_freeze','candidate_allocation','production_signing','technical_seal','promotion','tagging','publication') -Code 'mir42-release-go-controller-shape'
  if ([string]$record.current_controller_state.programme_path -cne '.mir/releases/governance/mir4/MIR42-Nine-Target-Release-Cut-ProgrammeV1.json' -or
      [string]$record.current_controller_state.programme_status -cne 'active-current-4.2-release-cut-pre-freeze-no-transition-authority' -or
      @($record.current_controller_state.PSObject.Properties | Where-Object { $_.Name -notin @('programme_path','programme_status') -and $_.Value -isnot [bool] }).Count -ne 0 -or
      @($record.current_controller_state.PSObject.Properties | Where-Object { $_.Name -notin @('programme_path','programme_status') -and [bool]$_.Value }).Count -ne 0) {
    throw '[mir42-release-go-controller-state]'
  }
  Assert-MIR42ReleaseAssetProperties -Value $record.final_byte_binding -Expected @('candidate_manifest_path','technical_seal_path','frozen_inventory_path','required_binding') -Code 'mir42-release-go-binding-shape'
  if ([string]$record.final_byte_binding.candidate_manifest_path -cne 'deferred' -or
      [string]$record.final_byte_binding.technical_seal_path -cne 'deferred' -or
      [string]$record.final_byte_binding.frozen_inventory_path -cne 'deferred' -or
      [string]::IsNullOrWhiteSpace([string]$record.final_byte_binding.required_binding)) {
    throw '[mir42-release-go-binding-state]'
  }
  return $identity
}

function Read-MIR42NineTargetProtectedMainReadbackForPublication {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path)

  $identity = Read-MIR42SealRecord -Path $Path -Code 'mir42-release-go-main-readback'
  $record = $identity.record
  Assert-MIR42ReleaseAssetProperties -Value $record -Expected @(
    'schema','kind','status','scope','source','primary_main','protected_pull_request','promotion_transport','source_rebinding',
    'candidate_manifest','technical_seal','current_programme','direct_predecessors','governed_offline_restore_drill','targets',
    'target_assets','proofs','main_readback_verified','remote_mutation_performed','protected_main_promotion_authorized',
    'human_go_required_after_main_readback','tagging_authorized','publication_authorized','record_sha256'
  ) -Code 'mir42-release-go-main-readback-shape'
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42NineTargetProtectedMainReadbackV1' -or
      [string]$record.status -cne 'MIR-4.2-NINE-TARGET-SEALED-ON-MAIN-AWAITING-HUMAN-PLAYTEST' -or [string]$record.scope -cne 'nine-target' -or
      $record.main_readback_verified -isnot [bool] -or -not [bool]$record.main_readback_verified -or
      $record.remote_mutation_performed -isnot [bool] -or [bool]$record.remote_mutation_performed -or
      $record.protected_main_promotion_authorized -isnot [bool] -or [bool]$record.protected_main_promotion_authorized -or
      $record.human_go_required_after_main_readback -isnot [bool] -or -not [bool]$record.human_go_required_after_main_readback -or
      $record.tagging_authorized -isnot [bool] -or [bool]$record.tagging_authorized -or
      $record.publication_authorized -isnot [bool] -or [bool]$record.publication_authorized) {
    throw '[mir42-release-go-main-readback-state]'
  }
  foreach ($field in @('commit','tree','package_source_sha256')) {
    if ([string]$record.source.$field -cnotmatch '^[A-Fa-f0-9]{40,64}$' -or [string]$record.primary_main.$field -cnotmatch '^[A-Fa-f0-9]{40,64}$') { throw "[mir42-release-go-main-readback-source] $field" }
  }
  Assert-MIR42ReleaseAssetProperties -Value $record.candidate_manifest -Expected @('sha256','record_sha256') -Code 'mir42-release-go-main-readback-candidate-shape'
  Assert-MIR42ReleaseAssetProperties -Value $record.technical_seal -Expected @('sha256','record_sha256') -Code 'mir42-release-go-main-readback-seal-shape'
  foreach ($hash in @([string]$record.candidate_manifest.sha256,[string]$record.candidate_manifest.record_sha256,[string]$record.technical_seal.sha256,[string]$record.technical_seal.record_sha256)) {
    if ($hash -cnotmatch '^[A-F0-9]{64}$') { throw '[mir42-release-go-main-readback-binding]' }
  }
  if ([string]$record.source_rebinding.qualified_tree -cne [string]$record.source.tree -or
      [string]$record.source_rebinding.promoted_main_tree -cne [string]$record.primary_main.tree -or
      [string]$record.source_rebinding.package_source_sha256 -cne [string]$record.source.package_source_sha256 -or
      -not [bool]$record.source_rebinding.package_bytes_preserved -or -not [bool]$record.source_rebinding.explicit_commit_rebinding) {
    throw '[mir42-release-go-main-readback-rebinding]'
  }
  Assert-MIR42SealTargetSet -Rows @($record.target_assets) -Scope 'nine-target' -Code 'mir42-release-go-main-readback-targets'
  if ((@($record.targets | ForEach-Object { [string]$_ }) -join '|') -cne ($script:MIR42ReleaseAssetTargets -join '|')) { throw '[mir42-release-go-main-readback-target-list]' }
  return $identity
}

function Write-MIR42NineTargetPublicationAuthorization {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$PrimaryRepoRoot,[Parameter(Mandatory)][string]$OutputPath)

  if (-not (Test-MIR4BootstrapRecordHash -Record $Record)) { throw '[mir42-release-go-output-record]' }
  $primary = (Resolve-Path -LiteralPath $PrimaryRepoRoot).Path
  $outputRoot = Join-Path $primary 'build/release-authorization'
  try {
    $output = Assert-MIR4DescendantPath -Root $outputRoot -Path $OutputPath
    $null = Assert-MIR4NoReparseAncestors -Root $primary -Path $output
  } catch { throw '[mir42-release-go-output-containment]' }
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4BootstrapCanonicalJson -Value $Record) + "`n")
  if (Test-Path -LiteralPath $output -PathType Leaf) {
    if ([Convert]::ToHexString([IO.File]::ReadAllBytes($output)) -ne [Convert]::ToHexString($bytes)) { throw '[mir42-release-go-output-existing-authority-preserved]' }
  } else {
    $parent = Split-Path -Parent $output
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $stream = [IO.File]::Open($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
  }
  return Read-MIR42SealRecord -Path $output -Code 'mir42-release-go-output'
}

function New-MIR42NineTargetPublicationAuthorization {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$PrimaryRepoRoot,
    [Parameter(Mandatory)][string]$MaintainerAuthorizationPath,
    [Parameter(Mandatory)][string]$MainReadbackPath,
    [Parameter(Mandatory)][string]$FrozenInventoryPath,
    [Parameter(Mandatory)][string]$OutputPath
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authorization = Read-MIR42NineTargetWrittenReleaseAuthorization -Path $MaintainerAuthorizationPath
  $mainReadback = Read-MIR42NineTargetProtectedMainReadbackForPublication -Path $MainReadbackPath
  $inventory = Read-MIR42NineTargetReleaseAssetInventory -Path $FrozenInventoryPath
  $liveMain = Get-MIR42PrimaryMainSnapshot -PrimaryRepoRoot $PrimaryRepoRoot
  $record = $mainReadback.record
  foreach ($field in @('commit','tree','package_source_sha256','remote_commit')) {
    if ([string]$liveMain.$field -cne [string]$record.primary_main.$field) { throw "[mir42-release-go-live-main-binding] $field" }
  }
  if ([string]$liveMain.branch -cne 'main' -or -not [bool]$liveMain.working_tree_clean -or
      [string]$liveMain.remote -cne 'origin' -or [string]$liveMain.ref -cne 'refs/heads/main') { throw '[mir42-release-go-live-main-state]' }
  foreach ($field in @('commit','tree','package_source_sha256')) {
    if ([string]$inventory.record.source.$field -cne [string]$record.source.$field) { throw "[mir42-release-go-inventory-source] $field" }
  }
  foreach ($binding in @('candidate_manifest','technical_seal')) {
    foreach ($field in @('sha256','record_sha256')) {
      if ([string]$inventory.record.$binding.$field -cne [string]$record.$binding.$field) { throw "[mir42-release-go-inventory-binding] $binding/$field" }
    }
  }
  Assert-MIR42SealTargetSet -Rows @($inventory.record.package_assets) -Scope 'nine-target' -Code 'mir42-release-go-inventory-targets'
  for ($index = 0; $index -lt $script:MIR42ReleaseAssetTargets.Count; $index++) {
    $fromMain = $record.target_assets[$index]
    $fromInventory = $inventory.record.package_assets[$index]
    foreach ($field in @('target','distribution_version','content_sha256','entry_count')) {
      if ([string]$fromMain.$field -cne [string]$fromInventory.$field) { throw "[mir42-release-go-inventory-target] $field/$index" }
    }
    if ([string]$fromMain.archive_sha256 -cne [string]$fromInventory.sha256) { throw "[mir42-release-go-inventory-target] archive_sha256/$index" }
  }
  $output = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42NineTargetPublicationAuthorizationV1'
    status = 'MIR-4.2-NINE-TARGET-WRITTEN-GO-BOUND-TO-MAIN-AND-FROZEN-ASSETS'
    release = [ordered]@{source_version='4.2.0';tag='v4.2.0'}
    written_maintainer_authorization = [ordered]@{
      path=(Resolve-Path -LiteralPath $MaintainerAuthorizationPath).Path;sha256=[string]$authorization.sha256;record_sha256=[string]$authorization.record.record_sha256
      recorded_from_user_turn_date=[string]$authorization.record.recorded_from_user_turn_date
      acceptance_type='written-conditional-go-with-playtest-waiver'
      gameplay_receipt_claimed=$false
      additional_playtest_prompt_waived=$true
      experimental_f210_consent='qualified-experimental-consent-recorded'
    }
    source = $record.source
    primary_main = [ordered]@{commit=[string]$liveMain.commit;tree=[string]$liveMain.tree;package_source_sha256=[string]$liveMain.package_source_sha256;remote='origin';ref='refs/heads/main'}
    main_readback = [ordered]@{path=(Resolve-Path -LiteralPath $MainReadbackPath).Path;sha256=[string]$mainReadback.sha256;record_sha256=[string]$record.record_sha256}
    candidate_manifest = $record.candidate_manifest
    technical_seal = $record.technical_seal
    frozen_release_asset_inventory = [ordered]@{path=(Resolve-Path -LiteralPath $FrozenInventoryPath).Path;sha256=[string]$inventory.sha256;record_sha256=[string]$inventory.record.record_sha256;asset_root_file_set_sha256=[string]$inventory.record.asset_root_file_set_sha256}
    target_assets = @($inventory.record.package_assets | ForEach-Object { [ordered]@{target=[string]$_.target;distribution_version=[string]$_.distribution_version;archive_sha256=[string]$_.sha256;content_sha256=[string]$_.content_sha256;entry_count=[int]$_.entry_count} })
    tagging_authorized = $true
    publication_scope = 'github-release-only'
    github_publication_authorized = $true
    mod_portal_upload_authorized = $false
    mod_portal_upload_disposition = 'not-claimed-by-this-github-release-authorization'
    publication_authorized = $true
    public_readback_required_after_publication = $true
    record_sha256 = ''
  }
  $output.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $output
  return Write-MIR42NineTargetPublicationAuthorization -Record $output -PrimaryRepoRoot $PrimaryRepoRoot -OutputPath $OutputPath
}

function Assert-MIR42NineTargetDownloadedReleaseBytes {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$FrozenInventoryPath,
    [Parameter(Mandatory)][string]$DownloadedAssetRoot
  )

  $inventory = Read-MIR42NineTargetReleaseAssetInventory -Path $FrozenInventoryPath
  $downloaded = Get-MIR42ReleaseAssetFileMap -Root $DownloadedAssetRoot -Code 'mir42-release-assets-download'
  $expected = @($inventory.record.github_assets | ForEach-Object { [string]$_.name })
  Assert-MIR42ReleaseAssetExactFileSet -Map $downloaded -Expected $expected -Code 'mir42-release-assets-download'
  foreach ($asset in @($inventory.record.github_assets)) {
    $actual = Get-MIR42ReleaseAssetFile -Map $downloaded -Path ([string]$asset.name) -Code 'mir42-release-assets-download'
    if ([string]$actual.sha256 -cne [string]$asset.sha256 -or [int64]$actual.bytes -ne [int64]$asset.bytes) {
      throw "[mir42-release-assets-downloaded-byte] $([string]$asset.name)"
    }
  }
  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42NineTargetDownloadedReleaseByteVerificationV1'
    status = 'MIR-4.2-NINE-TARGET-DOWNLOADED-BYTES-VERIFIED-NONAUTHORIZING'
    frozen_inventory = [ordered]@{sha256=[string]$inventory.sha256;record_sha256=[string]$inventory.record.record_sha256}
    downloaded_asset_count = @($inventory.record.github_assets).Count
    downloaded_bytes_verified = $true
    public_readback_verified = $false
    human_go_required_after_main_readback = $true
    tagging_authorized = $false
    publication_authorized = $false
  }
}

function Invoke-MIR42DefaultPublicReleaseObserver {
  param([Parameter(Mandatory)][string]$Repository,[Parameter(Mandatory)][string]$Tag)

  $gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue
  if ($null -eq $gh) { throw '[mir42-release-assets-public-observer-client-missing]' }
  try {
    $raw = & $gh.Source api --hostname github.com ("repos/" + $Repository + "/releases/tags/" + $Tag) 2>$null
    if ($LASTEXITCODE -ne 0 -or @($raw).Count -eq 0) { throw 'gh-failed' }
    $release = ($raw -join "`n") | ConvertFrom-Json -Depth 100 -DateKind String
  } catch { throw '[mir42-release-assets-public-observer-live-read]' }
  return [pscustomobject][ordered]@{
    kind = 'MIR42PublicReleaseObserverV1'
    transport = 'github-cli-api'
    synthetic = $false
    repository = $Repository
    tag = [string]$release.tag_name
    release_id = [int64]$release.id
    url = [string]$release.html_url
    draft = [bool]$release.draft
    network_calls = 1
    assets = @($release.assets | ForEach-Object {
      [pscustomobject][ordered]@{name=[string]$_.name;sha256=([string]$_.digest -replace '^sha256:', '').ToUpperInvariant();bytes=[int64]$_.size}
    })
  }
}

function Assert-MIR42NineTargetLivePublicReleaseObservation {
  param([Parameter(Mandatory)]$Observation,[Parameter(Mandatory)]$Inventory)

  Assert-MIR42ReleaseAssetProperties -Value $Observation -Expected @('kind','transport','synthetic','repository','tag','release_id','url','draft','network_calls','assets') -Code 'mir42-release-assets-public-observer'
  Assert-MIR42ReleaseAssetBooleanFlags -Value $Observation -Fields @('synthetic','draft') -Code 'mir42-release-assets-public-observer'
  if ([string]$Observation.kind -cne 'MIR42PublicReleaseObserverV1' -or [bool]$Observation.synthetic -or
      [string]$Observation.transport -cne 'github-cli-api' -or [string]$Observation.repository -cne 'Julesc013/more-infinite-research' -or
      [string]$Observation.tag -cne [string]$Inventory.record.release.tag -or [int64]$Observation.release_id -le 0 -or
      [string]$Observation.url -cne ('https://github.com/Julesc013/more-infinite-research/releases/tag/' + [string]$Inventory.record.release.tag) -or [bool]$Observation.draft -or
      [int64]$Observation.network_calls -le 0) { throw '[mir42-release-assets-public-observer-state]' }
  $expected = @($Inventory.record.github_assets)
  if (@($Observation.assets).Count -ne $expected.Count) { throw '[mir42-release-assets-public-observer-count]' }
  $observedByName = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($asset in @($Observation.assets)) {
    Assert-MIR42ReleaseAssetProperties -Value $asset -Expected @('name','sha256','bytes') -Code 'mir42-release-assets-public-observer-asset'
    if ([string]::IsNullOrWhiteSpace([string]$asset.name) -or -not $observedByName.TryAdd([string]$asset.name, $asset)) {
      throw "[mir42-release-assets-public-observer-duplicate] $([string]$asset.name)"
    }
  }
  foreach ($asset in $expected) {
    if (-not $observedByName.ContainsKey([string]$asset.name)) { throw "[mir42-release-assets-public-observer-missing] $([string]$asset.name)" }
    $actual = $observedByName[[string]$asset.name]
    if ([string]$actual.sha256 -cne [string]$asset.sha256 -or [int64]$actual.bytes -ne [int64]$asset.bytes) {
      throw "[mir42-release-assets-public-observer-asset] $([string]$asset.name)"
    }
  }
}

function Get-MIR42NineTargetPublicDownloadedReleaseReadback {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$FrozenInventoryPath,
    [Parameter(Mandatory)][string]$DownloadedAssetRoot
  )

  $inventory = Read-MIR42NineTargetReleaseAssetInventory -Path $FrozenInventoryPath
  $observation = Invoke-MIR42DefaultPublicReleaseObserver -Repository 'Julesc013/more-infinite-research' -Tag ([string]$inventory.record.release.tag)
  Assert-MIR42NineTargetLivePublicReleaseObservation -Observation $observation -Inventory $inventory
  $verification = Assert-MIR42NineTargetDownloadedReleaseBytes -FrozenInventoryPath $FrozenInventoryPath -DownloadedAssetRoot $DownloadedAssetRoot
  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42NineTargetPublicDownloadedReleaseReadbackV1'
    status = 'MIR-4.2-NINE-TARGET-PUBLIC-DOWNLOADED-BYTES-VERIFIED-NONAUTHORIZING'
    frozen_inventory = $verification.frozen_inventory
    live_release = [ordered]@{repository=[string]$observation.repository;tag=[string]$observation.tag;release_id=[int64]$observation.release_id;url=[string]$observation.url;transport=[string]$observation.transport;network_calls=[int64]$observation.network_calls}
    downloaded_asset_count = [int]$verification.downloaded_asset_count
    downloaded_bytes_verified = $true
    public_readback_verified = $true
    human_go_required_after_main_readback = $true
    tagging_authorized = $false
    publication_authorized = $false
  }
}
