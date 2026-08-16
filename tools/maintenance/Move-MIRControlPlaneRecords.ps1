param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$directoryMoves = [ordered]@{
  "approved-delta" = ".mir/releases/deltas"
  ".mir/candidate-closures" = ".mir/releases/closures"
  ".mir/release-transitions" = ".mir/releases/transitions"
  ".mir/backports" = ".mir/releases/backports"
  ".mir/generated" = ".mir/views"
  ".mir/changes" = ".mir/lifecycle/changes"
  ".mir/incidents" = ".mir/lifecycle/incidents"
  ".mir/tasks" = ".mir/lifecycle/tasks"
}
$releaseNames = @(
  "2.4.9.json", "2.5.0.json", "3.2.1.json", "3.2.2.json",
  "3.2.3.json", "3.2.4.json", "3.2.5.json", "current.json"
)

function Get-MIRMigrationSha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

$moves = [Collections.Generic.List[object]]::new()
foreach ($sourceRoot in $directoryMoves.Keys) {
  $source = Join-Path $RepoRoot $sourceRoot
  $targetRoot = [string]$directoryMoves[$sourceRoot]
  $target = Join-Path $RepoRoot $targetRoot
  $sourceFiles = @(Get-ChildItem -LiteralPath $source -Recurse -File -ErrorAction SilentlyContinue)
  $targetFiles = @(Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue)
  if ($sourceFiles.Count -gt 0 -and $targetFiles.Count -gt 0) {
    throw "Refusing duplicate Control Plane authorities: $sourceRoot and $targetRoot"
  }
  foreach ($file in $sourceFiles) {
    $suffix = [IO.Path]::GetRelativePath($source, $file.FullName).Replace("\", "/")
    $moves.Add([pscustomobject][ordered]@{
      from = "$sourceRoot/$suffix"
      to = "$targetRoot/$suffix"
      sha256 = Get-MIRMigrationSha256 -Path $file.FullName
    })
  }
  if ($sourceFiles.Count -eq 0 -and $targetFiles.Count -eq 0) {
    throw "Control Plane authority is absent from both legacy and canonical roots: $sourceRoot"
  }
}
foreach ($name in $releaseNames) {
  $from = ".mir/releases/$name"
  $to = ".mir/releases/records/$name"
  $source = Join-Path $RepoRoot $from
  $target = Join-Path $RepoRoot $to
  $sourceExists = Test-Path -LiteralPath $source -PathType Leaf
  $targetExists = Test-Path -LiteralPath $target -PathType Leaf
  if ($sourceExists -and $targetExists) { throw "Refusing duplicate release record: $from and $to" }
  if (-not $sourceExists -and -not $targetExists) { throw "Release record is absent: $name" }
  $identityPath = if ($sourceExists) { $source } else { $target }
  if ($sourceExists) {
    $moves.Add([pscustomobject][ordered]@{from=$from;to=$to;sha256=(Get-MIRMigrationSha256 -Path $identityPath)})
  }
}

if ($Apply) {
  foreach ($move in @($moves)) {
    $source = Join-Path $RepoRoot ([string]$move.from)
    $target = Join-Path $RepoRoot ([string]$move.to)
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
    Move-Item -LiteralPath $source -Destination $target
    $after = Get-MIRMigrationSha256 -Path $target
    if ($after -cne [string]$move.sha256) { throw "Migration changed bytes: $($move.from)" }
  }

  $receiptPath = Join-Path $RepoRoot ".mir/evidence/receipts/control-plane-paths-v1.json"
  $receiptRows = @($moves | Sort-Object from | ForEach-Object {
    [pscustomobject][ordered]@{from=[string]$_.from;to=[string]$_.to;sha256=[string]$_.sha256}
  })
  $aggregateText = @($receiptRows | ForEach-Object { "$($_.from)|$($_.to)|$($_.sha256)" }) -join "`n"
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $aggregate = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($aggregateText))).Replace("-", "") }
  finally { $sha.Dispose() }
  $receipt = [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-control-plane-path-migration-v1"
    migration = "dual-read-single-write"
    source_commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
    package_bytes_changed = $false
    entry_count = $receiptRows.Count
    aggregate_sha256 = $aggregate
    aliases = ".mir/control/aliases.yml"
    canonical_paths = ".mir/control/paths.yml"
    entries = $receiptRows
  }
  $null = New-Item -ItemType Directory -Path (Split-Path -Parent $receiptPath) -Force
  [IO.File]::WriteAllText($receiptPath, (($receipt | ConvertTo-Json -Depth 8) + "`n"), $utf8NoBom)
}

[pscustomobject][ordered]@{
  schema = 1
  migration = "mir-control-plane-paths-v1"
  mode = if ($Apply) { "apply" } else { "preview" }
  changed = $moves.Count
  entries = $moves.Count
  receipt = ".mir/evidence/receipts/control-plane-paths-v1.json"
} | ConvertTo-Json -Depth 4
