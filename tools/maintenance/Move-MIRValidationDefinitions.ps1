param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$moves = [ordered]@{
  "fixtures/compat-matrix/claims.json" = "spec/compatibility/claims.json"
  "fixtures/compat-matrix/support-lanes.json" = "spec/compatibility/support-lanes.json"
  "fixtures/compat-matrix/expected-failures.json" = "validation/assertions/expected-failures.json"
  "fixtures/compat-matrix/known-exclusions.json" = "validation/adapters/portal-exclusions.json"
  "fixtures/compat-matrix/expected-scenarios.json" = "validation/scenarios/runtime.json"
  "fixtures/compat-matrix/manual-scenarios.json" = "validation/scenarios/manual.json"
  "fixtures/compat-matrix/local-library-scenarios.json" = "validation/scenarios/local-2.1.json"
  "fixtures/compat-matrix/local-library-scenarios-2.0.json" = "validation/scenarios/local-2.0.json"
  ".mir/control-plane/baselines/2.5.0-p9-v4.json" = "validation/baselines/control/2.5.0-p9-v4.json"
  ".mir/control-plane/baselines/3.2.2-v4.json" = "validation/baselines/control/3.2.2-v4.json"
  ".mir/control-plane/baselines/3.2.2-v5-replay.json" = "validation/baselines/control/3.2.2-v5-replay.json"
}

function Get-MIRActiveDefinitionFiles {
  $roots = @(".github", ".mir", "docs", "scripts", "validation", "tools", "spec", "fixtures")
  $files = @()
  foreach ($root in $roots) {
    $absolute = Join-Path $RepoRoot $root
    if (Test-Path -LiteralPath $absolute) { $files += Get-ChildItem -LiteralPath $absolute -Recurse -File }
  }
  foreach ($name in @("AGENTS.md", "CONTRIBUTING.md")) {
    $absolute = Join-Path $RepoRoot $name
    if (Test-Path -LiteralPath $absolute -PathType Leaf) { $files += Get-Item -LiteralPath $absolute }
  }
  return @($files | Where-Object {
    $relative = [IO.Path]::GetRelativePath($RepoRoot, $_.FullName).Replace("\", "/")
    $_.Extension -in @(".json", ".md", ".ps1", ".psm1", ".yml", ".yaml") -and
    $relative -notlike ".mir/evidence/*" -and
    $relative -notlike ".mir/target-lines/*" -and
    $relative -notlike ".mir/releases/*" -and
    $relative -notlike ".mir/candidate-closures/*" -and
    $relative -notlike ".mir/release-transitions/*" -and
    $relative -notlike ".mir/backports/*" -and
    $relative -notlike ".mir/backport-*.json" -and
    $relative -ne ".mir/performance-campaign.json" -and
    $relative -notlike ".mir/performance-campaigns/*" -and
    $relative -notlike "docs/archive/*" -and
    $relative -notlike "docs/releases/*" -and
    $relative -ne "README.md" -and
    $relative -ne "tools/maintenance/Move-MIRValidationDefinitions.ps1" -and
    $relative -ne ".mir/control/aliases.yml"
  } | Sort-Object FullName -Unique)
}

$moveCount = 0
$moved = @()
foreach ($from in $moves.Keys) {
  $source = Join-Path $RepoRoot $from
  $target = Join-Path $RepoRoot $moves[$from]
  $sourceExists = Test-Path -LiteralPath $source -PathType Leaf
  $targetExists = Test-Path -LiteralPath $target -PathType Leaf
  if ($sourceExists -and $targetExists) {
    throw "Refusing duplicate definition authorities: $from and $($moves[$from])"
  }
  if ($sourceExists) {
    $moveCount++
    $moved += $moves[$from]
    if ($Apply) {
      $null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
      Move-Item -LiteralPath $source -Destination $target
    }
  } elseif (-not $targetExists) {
    throw "Definition is absent from both legacy and canonical paths: $from"
  }
}

$referenceFiles = @()
foreach ($file in Get-MIRActiveDefinitionFiles) {
  $text = Get-Content -Raw -LiteralPath $file.FullName
  $updated = $text
  foreach ($from in $moves.Keys) {
    $updated = $updated.Replace($from, $moves[$from])
    $updated = $updated.Replace($from.Replace("/", "\"), $moves[$from].Replace("/", "\"))
  }
  if ($updated -ne $text) {
    $referenceFiles += [IO.Path]::GetRelativePath($RepoRoot, $file.FullName).Replace("\", "/")
    if ($Apply) { [IO.File]::WriteAllText($file.FullName, $updated, $utf8NoBom) }
  }
}

[ordered]@{
  schema = 1
  migration = "mir-validation-definitions-v1"
  mode = if ($Apply) { "apply" } else { "preview" }
  definitions = $moves.Count
  moves = $moveCount
  reference_files = $referenceFiles.Count
  changed = $moveCount + $referenceFiles.Count
  moved = @($moved)
  rewritten = @($referenceFiles)
} | ConvertTo-Json -Depth 6
