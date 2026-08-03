param(
  [Parameter(Mandatory)][ValidateCount(2, 16)][string[]]$ReceiptPath,
  [string]$ManifestPath = ".mir/backports/2.5.0.json",
  [string]$OutputPath = "",
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not [IO.Path]::IsPathRooted($ManifestPath)) { $ManifestPath = Join-Path $repo $ManifestPath }
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
$receipts = [Collections.Generic.List[object]]::new()

foreach ($pathValue in $ReceiptPath) {
  $path = (Resolve-Path -LiteralPath $pathValue).Path
  $receipt = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if ([int]$receipt.schema -ne 1 -or [string]$receipt.target_release -ne [string]$manifest.target_release -or
      [string]$receipt.target_factorio -ne [string]$manifest.target_factorio -or
      [string]$receipt.baseline_tag_commit -ne [string]$manifest.baseline.tag_commit -or
      [string]$receipt.source_tag_commit -ne [string]$manifest.source.tag_commit -or
      [string]$receipt.preintegration_tag_commit -ne [string]$manifest.integration.preintegration_commit -or
      [string]$receipt.integration_tree -ne [string]$manifest.expected_target.integration_tree -or
      [string]$receipt.archive_sha256 -ne [string]$manifest.expected_target.archive_sha256 -or
      [string]$receipt.package_content_sha256 -ne [string]$manifest.expected_target.package_content_sha256 -or
      [int64]$receipt.bytes -ne [int64]$manifest.expected_target.bytes -or
      [int]$receipt.entries -ne [int]$manifest.expected_target.entries) {
    throw "Backport reconstruction receipt disagrees with the governed manifest: $path"
  }
  $parents = @($receipt.integration_parents | ForEach-Object { [string]$_ })
  if ($parents.Count -ne 2 -or $parents[0] -ne [string]$manifest.integration.preintegration_commit -or $parents[1] -ne [string]$manifest.source.tag_commit) {
    throw "Backport reconstruction receipt has the wrong target-first/source-second ancestry: $path"
  }

  $material = [ordered]@{}
  foreach ($property in $receipt.PSObject.Properties) {
    if ($property.Name -notin @("receipt_material_sha256", "reconstructed_at")) { $material[$property.Name] = $property.Value }
  }
  $materialBytes = [Text.UTF8Encoding]::new($false).GetBytes(($material | ConvertTo-Json -Depth 20 -Compress))
  $materialSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($materialBytes))
  if ($materialSha256 -ne [string]$receipt.receipt_material_sha256) { throw "Backport reconstruction receipt material digest is invalid: $path" }

  $commit = [string]$receipt.integration_commit
  & git -C $repo cat-file -e "$commit`^{commit}" 2>$null
  if ($LASTEXITCODE -ne 0) { throw "Backport reconstruction commit is absent from the repository object store: $commit" }
  $actualTree = ([string](& git -C $repo rev-parse "$commit`^{tree}")).Trim()
  $actualParents = @((([string](& git -C $repo show -s --format=%P $commit)).Trim()) -split " ")
  if ($actualTree -ne [string]$receipt.integration_tree -or (($actualParents -join "`n") -cne ($parents -join "`n"))) {
    throw "Backport reconstruction receipt does not match its Git commit: $path"
  }
  $receiptSha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  $reconstructedAt = ([DateTimeOffset]$receipt.reconstructed_at).ToUniversalTime().ToString("o")
  $receipts.Add([pscustomobject][ordered]@{path=$path;receipt_sha256=$receiptSha256;integration_commit=$commit;receipt_material_sha256=$materialSha256;reconstructed_at=$reconstructedAt})
}

$commitIds = @($receipts.integration_commit | Sort-Object -Unique)
$materialIds = @($receipts.receipt_material_sha256 | Sort-Object -Unique)
if ($commitIds.Count -ne 1 -or $materialIds.Count -ne 1) { throw "Independent backport reconstructions are not deterministic." }

$portableReceipts = @($receipts | ForEach-Object -Begin { $index = 0 } -Process {
  $index++
  [pscustomobject][ordered]@{rehearsal="R$index";receipt_sha256=[string]$_.receipt_sha256;reconstructed_at=[string]$_.reconstructed_at}
})
$result = [pscustomobject][ordered]@{
  schema = 1
  kind = "mir-v5-dual-parent-reconstruction"
  status = "passed"
  target_release = [string]$manifest.target_release
  target_candidate = [string]$manifest.expected_target.candidate_id
  baseline_tag_commit = [string]$manifest.baseline.tag_commit
  source_tag_commit = [string]$manifest.source.tag_commit
  preintegration_tag_commit = [string]$manifest.integration.preintegration_commit
  rehearsals = $receipts.Count
  integration_commit = [string]$commitIds[0]
  integration_parents = @([string]$manifest.integration.preintegration_commit, [string]$manifest.source.tag_commit)
  integration_tree = [string]$manifest.expected_target.integration_tree
  archive_sha256 = [string]$manifest.expected_target.archive_sha256
  package_content_sha256 = [string]$manifest.expected_target.package_content_sha256
  bytes = [int64]$manifest.expected_target.bytes
  entries = [int]$manifest.expected_target.entries
  receipt_material_sha256 = [string]$materialIds[0]
  receipts = $portableReceipts
}
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  if (-not [IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $repo $OutputPath }
  $outputDirectory = Split-Path -Parent $OutputPath
  if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
  [IO.File]::WriteAllText($OutputPath, (($result | ConvertTo-Json -Depth 12) + "`n"), [Text.UTF8Encoding]::new($false))
}
$result | ConvertTo-Json -Depth 12
