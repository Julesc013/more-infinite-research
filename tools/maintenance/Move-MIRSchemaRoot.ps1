[CmdletBinding()]
param(
  [string]$RepoRoot = "",
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
}
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

$files = [Collections.Generic.List[string]]::new()
foreach ($root in @("scripts", "validation", "docs", ".github/workflows", ".mir/tasks")) {
  $rootPath = Join-Path $repo $root
  if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { continue }
  Get-ChildItem -LiteralPath $rootPath -Recurse -File |
    Where-Object {
      $_.FullName -notlike (Join-Path $repo "docs/archive/*") -and
      $_.Extension -in @(".ps1", ".psm1", ".json", ".yml", ".yaml", ".md")
    } |
    ForEach-Object { $files.Add($_.FullName) }
}
foreach ($relative in @(
  ".mir/fixtures.yml",
  ".mir/modules.yml"
)) {
  $path = Join-Path $repo $relative
  if (Test-Path -LiteralPath $path -PathType Leaf) { $files.Add($path) }
}

$changed = [Collections.Generic.List[string]]::new()
foreach ($path in @($files | Sort-Object -Unique)) {
  $before = [IO.File]::ReadAllText($path)
  $after = $before.Replace("verification/schema/", "spec/schemas/")
  $after = $after.Replace("verification/schema", "spec/schemas")
  $after = $after.Replace("verification\schema\", "spec\schemas\")
  $after = $after.Replace("verification\schema", "spec\schemas")
  if ($after -ceq $before) { continue }
  $changed.Add($path.Substring($repo.Length + 1).Replace("\", "/"))
  if ($Apply) {
    [IO.File]::WriteAllText($path, $after, [Text.UTF8Encoding]::new($false))
  }
}

[pscustomobject][ordered]@{
  schema = 1
  mode = if ($Apply) { "applied" } else { "preview" }
  changed = $changed.Count
  files = @($changed)
} | ConvertTo-Json -Depth 4
