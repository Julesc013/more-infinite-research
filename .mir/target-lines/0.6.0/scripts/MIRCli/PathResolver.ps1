function Get-MIRRepoRoot {
  param([string]$StartPath = $PSScriptRoot)

  $current = Resolve-Path -LiteralPath $StartPath
  while ($current) {
    if (Test-Path -LiteralPath (Join-Path $current ".git")) { return $current.Path }
    $parent = Split-Path -Parent $current
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current.Path) { break }
    $current = Resolve-Path -LiteralPath $parent
  }

  throw "Could not locate repository root from $StartPath."
}

function Resolve-MIRPath {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Path
  )

  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepoRoot $Path
}

function Resolve-MIRFactorioBin {
  param([string]$Path = $env:FACTORIO_BIN)

  $candidates = @()
  if (-not [string]::IsNullOrWhiteSpace($Path) -and $Path -ne "auto") { $candidates += $Path }
  $candidates += @(
    "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe",
    "C:\Program Files (x86)\Steam\steamapps\common\Factorio\bin\x64\factorio.exe",
    "C:\Program Files\Factorio\bin\x64\factorio.exe"
  )

  foreach ($candidate in $candidates) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  throw "Could not find factorio.exe. Pass -FactorioBin or set FACTORIO_BIN."
}
