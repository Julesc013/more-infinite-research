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
$repoPrefix = $repo.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$deprecatedRoots = @(".work")
$present = [Collections.Generic.List[string]]::new()
$removed = [Collections.Generic.List[string]]::new()

foreach ($relative in $deprecatedRoots) {
  $target = [IO.Path]::GetFullPath((Join-Path $repo $relative))
  if (-not $target.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Deprecated output root escaped the repository: $target"
  }
  if (-not (Test-Path -LiteralPath $target)) { continue }

  $present.Add($relative)
  $item = Get-Item -LiteralPath $target -Force
  if (-not $item.PSIsContainer) { throw "Deprecated output root is not a directory: $target" }
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Deprecated output root is a reparse point: $target"
  }
  $nestedLinks = @(Get-ChildItem -LiteralPath $target -Recurse -Force -ErrorAction Stop | Where-Object {
    ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
  })
  if ($nestedLinks.Count -ne 0) { throw "Deprecated output root contains a reparse point: $($nestedLinks[0].FullName)" }
  if (Test-Path -LiteralPath (Join-Path $target ".git")) {
    throw "Deprecated output root contains a nested Git worktree: $target"
  }

  $tracked = @(& git -C $repo ls-files -- "$relative/**")
  if ($LASTEXITCODE -ne 0) { throw "Unable to inspect tracked files under $relative/." }
  if ($tracked.Count -ne 0) { throw "Deprecated output root contains tracked files: $relative/" }

  if ($Apply) {
    if (@(Get-Process -Name factorio -ErrorAction SilentlyContinue).Count -ne 0) {
      throw "Refusing to remove the deprecated .work root while Factorio is running."
    }
    Remove-Item -LiteralPath $target -Recurse -Force
    $removed.Add($relative)
  }
}

[pscustomobject][ordered]@{
  schema = 1
  mode = if ($Apply) { "applied" } else { "preview" }
  present = @($present)
  removed = @($removed)
  canonical_roots = @("build", "dist")
} | ConvertTo-Json -Depth 4
