param(
  [string]$RepoRoot = "",
  [string]$ManifestPath = ".mir/backports/2.5.0.json",
  [string]$Source = "",
  [string]$Baseline = "",
  [string]$Target = "",
  [Parameter(Mandatory)][string]$Worktree,
  [string]$ReceiptPath = "",
  [switch]$KeepWorktree
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not [IO.Path]::IsPathRooted($ManifestPath)) { $ManifestPath = Join-Path $RepoRoot $ManifestPath }
$Worktree = [IO.Path]::GetFullPath($Worktree)
if (Test-Path -LiteralPath $Worktree) { throw "Materialization worktree already exists: $Worktree" }

& (Join-Path $PSScriptRoot "Test-MIRBackportManifest.ps1") -RepoRoot $RepoRoot -ManifestPath $ManifestPath
if ($LASTEXITCODE -ne 0) { throw "Backport manifest validation failed." }
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
if ($Source -and $Source -ne [string]$manifest.source.tag) { throw "--source disagrees with the manifest." }
if ($Baseline -and $Baseline -ne [string]$manifest.baseline.tag) { throw "--baseline disagrees with the manifest." }
if ($Target -and $Target -ne [string]$manifest.target_factorio) { throw "--target disagrees with the manifest." }
$baselineCommit = (& git -C $RepoRoot rev-parse "$($manifest.baseline.tag)^{commit}").Trim()
$sourceCommit = (& git -C $RepoRoot rev-parse "$($manifest.source.tag)^{commit}").Trim()
$projectionCommit = (& git -C $RepoRoot rev-parse "$($manifest.integration.preintegration_tag)^{commit}").Trim()

$created = $false
try {
  & git -C $RepoRoot worktree add --detach $Worktree $projectionCommit
  if ($LASTEXITCODE -ne 0) { throw "Unable to create reconstruction worktree." }
  $created = $true

  & git -C $Worktree merge --no-ff --no-commit $sourceCommit
  $mergeHead = Join-Path $Worktree ".git"
  $mergeHeadPath = (& git -C $Worktree rev-parse --git-path MERGE_HEAD).Trim()
  if (-not [IO.Path]::IsPathRooted($mergeHeadPath)) { $mergeHeadPath = Join-Path $Worktree $mergeHeadPath }
  if (-not (Test-Path -LiteralPath $mergeHeadPath -PathType Leaf)) {
    throw "The modern release did not enter an explicit merge state."
  }

  & git -C $Worktree read-tree --reset -u $projectionCommit
  if ($LASTEXITCODE -ne 0) { throw "Unable to apply the deterministic Factorio 2.0 projection tree." }

  & (Join-Path $Worktree "scripts\Sync-MIRTargetProfiles.ps1") -RepoRoot $Worktree -Check
  if ($LASTEXITCODE -ne 0) { throw "Reconstructed target profiles are stale." }
  & (Join-Path $Worktree "validation\tests\release\Test-MIRBackportSourceLock.ps1") -RepoRoot $Worktree
  if ($LASTEXITCODE -ne 0) { throw "Reconstructed backport source lock failed." }

  $parentCommitEpochs = @($projectionCommit, $sourceCommit | ForEach-Object {
    [int64](([string](& git -C $RepoRoot show -s --format=%ct $_)).Trim())
  })
  $deterministicCommitDate = [DateTimeOffset]::FromUnixTimeSeconds((($parentCommitEpochs | Measure-Object -Maximum).Maximum) + 1).ToString("yyyy-MM-ddTHH:mm:ssK")
  $previousAuthorDate = $env:GIT_AUTHOR_DATE
  $previousCommitterDate = $env:GIT_COMMITTER_DATE
  try {
    $env:GIT_AUTHOR_DATE = $deterministicCommitDate
    $env:GIT_COMMITTER_DATE = $deterministicCommitDate
    & git -C $Worktree -c user.name="MIR Backport Materializer" -c user.email="mir-backport@invalid" commit -m "merge(backport): project MIR $($manifest.source.release) onto Factorio $($manifest.target_factorio)"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create the two-parent reconstruction commit." }
  } finally {
    $env:GIT_AUTHOR_DATE = $previousAuthorDate
    $env:GIT_COMMITTER_DATE = $previousCommitterDate
  }
  $mergeCommit = (& git -C $Worktree rev-parse HEAD).Trim()
  $parents = @((& git -C $Worktree show -s --format=%P HEAD).Trim() -split ' ')
  if ($parents.Count -ne 2 -or $parents[0] -ne $projectionCommit -or $parents[1] -ne $sourceCommit) {
    throw "Reconstruction commit does not have the required target-first/source-second parent order."
  }
  & git -C $Worktree merge-base --is-ancestor $baselineCommit $mergeCommit
  if ($LASTEXITCODE -ne 0) { throw "Reconstruction lost the Factorio 2.0 baseline ancestry." }
  & git -C $Worktree merge-base --is-ancestor $sourceCommit $mergeCommit
  if ($LASTEXITCODE -ne 0) { throw "Reconstruction lost the immutable modern release ancestry." }
  $integrationTree = (& git -C $Worktree rev-parse "HEAD^{tree}").Trim()
  if ($integrationTree -ne [string]$manifest.expected_target.integration_tree) {
    throw "Reconstruction produced an unexpected integration tree."
  }

  $zip = Join-Path $Worktree ([string]$manifest.expected_target.archive)
  & (Join-Path $Worktree "scripts\Build-MIRPackage.ps1")
  if ($LASTEXITCODE -ne 0) { throw "First deterministic package build failed." }
  $firstSha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
  & (Join-Path $Worktree "scripts\Build-MIRPackage.ps1")
  if ($LASTEXITCODE -ne 0) { throw "Second deterministic package build failed." }
  $secondSha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
  if ($firstSha -ne $secondSha -or $secondSha -ne [string]$manifest.expected_target.archive_sha256) {
    throw "Reconstructed archive is not the exact deterministic target candidate."
  }

  . (Join-Path $Worktree "tools\lib\validation\PackageIdentity.ps1")
  $contentSha = Get-MIRZipContentFingerprint -Path $zip
  $zipItem = Get-Item -LiteralPath $zip
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($zip)
  try { $entryCount = @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) }).Count } finally { $archive.Dispose() }
  if ($contentSha -ne [string]$manifest.expected_target.package_content_sha256 -or
      $zipItem.Length -ne [int64]$manifest.expected_target.bytes -or
      $entryCount -ne [int]$manifest.expected_target.entries) {
    throw "Reconstructed package composition disagrees with the manifest."
  }

  if (-not $ReceiptPath) { $ReceiptPath = Join-Path $Worktree ".work\artifacts\backport-reconstruction\2.5.0.json" }
  if (-not [IO.Path]::IsPathRooted($ReceiptPath)) { $ReceiptPath = Join-Path $Worktree $ReceiptPath }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReceiptPath) | Out-Null
  $receiptMaterial = [ordered]@{
    schema = 1
    target_release = [string]$manifest.target_release
    target_factorio = [string]$manifest.target_factorio
    baseline_tag_commit = $baselineCommit
    source_tag_commit = $sourceCommit
    preintegration_tag_commit = $projectionCommit
    integration_commit = $mergeCommit
    integration_parents = $parents
    integration_tree = $integrationTree
    archive_sha256 = $secondSha
    package_content_sha256 = $contentSha
    bytes = $zipItem.Length
    entries = $entryCount
    package_path_classification = @($manifest.package_path_classification)
  }
  $receiptMaterialJson = $receiptMaterial | ConvertTo-Json -Depth 20 -Compress
  $receiptMaterialBytes = [Text.UTF8Encoding]::new($false).GetBytes($receiptMaterialJson)
  $receiptMaterialSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($receiptMaterialBytes))
  $receipt = [ordered]@{}
  foreach ($entry in $receiptMaterial.GetEnumerator()) {
    $receipt[$entry.Key] = $entry.Value
  }
  $receipt.receipt_material_sha256 = $receiptMaterialSha256
  $receipt.reconstructed_at = [DateTime]::UtcNow.ToString("o")
  [IO.File]::WriteAllText($ReceiptPath, ($receipt | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
  Write-Host "[ok] reconstructed MIR $($manifest.target_release) at $mergeCommit"
  Write-Host "[ok] receipt: $ReceiptPath"
} catch {
  if ($created -and -not $KeepWorktree) {
    & git -C $RepoRoot worktree remove --force $Worktree 2>$null
  }
  throw
}
