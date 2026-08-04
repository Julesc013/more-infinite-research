$mirOwnershipScript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../workspace/RepoPaths.ps1")).Path
$mirOwnershipModule = New-Module -Name MIRRepositoryOwnership -ArgumentList $mirOwnershipScript -ScriptBlock {
  param([string]$ScriptPath)
  . $ScriptPath
  Export-ModuleMember -Function Resolve-MIRPathOwnership, Resolve-MIRRepoPath
}
Import-Module $mirOwnershipModule -Force -Function Resolve-MIRPathOwnership, Resolve-MIRRepoPath

function Get-MIRCPRepoRoot {
  param([string]$RepoRoot = "")
  if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Join-Path $PSScriptRoot "../../.."
  }
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Resolve-MIRCPPathId {
  param(
    [Parameter(Mandatory)][string]$Id,
    [string]$Suffix = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $resolved = Resolve-MIRRepoPath -RepoRoot $repo -Id $Id
  $relative = [string]$resolved.relative_path
  if (-not [string]::IsNullOrWhiteSpace($Suffix)) {
    $relative = if ($relative -eq ".") { $Suffix.TrimStart("/") } else { "$($relative.TrimEnd('/'))/$($Suffix.TrimStart('/'))" }
  }
  return $relative
}

function Resolve-MIRCPPathToken {
  param(
    [Parameter(Mandatory)][string]$Path,
    [string]$RepoRoot = ""
  )
  if (-not $Path.StartsWith("path:", [StringComparison]::Ordinal)) { return $Path }
  if ($Path -notmatch '^path:(?<id>[a-z][a-z0-9.-]+)(?<suffix>/.*)?$') {
    throw "Invalid logical repository path token: $Path"
  }
  return Resolve-MIRCPPathId -Id $Matches.id -Suffix ([string]$Matches.suffix) -RepoRoot $RepoRoot
}

function Read-MIRCPJson {
  param(
    [Parameter(Mandatory)][string]$Path,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $Path = Resolve-MIRCPPathToken -Path $Path -RepoRoot $repo
  $resolved = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw "Control-plane JSON not found: $Path"
  }
  try {
    return Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json
  } catch {
    throw "Invalid control-plane JSON at ${Path}: $($_.Exception.Message)"
  }
}

function ConvertTo-MIRCPCanonicalValue {
  param($Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString("o", [Globalization.CultureInfo]::InvariantCulture) }
  if ($Value -is [datetimeoffset]) { return $Value.ToUniversalTime().ToString("o", [Globalization.CultureInfo]::InvariantCulture) }
  if ($Value -is [guid]) { return $Value.ToString("D") }
  if ($Value -is [string] -or $Value -is [bool] -or $Value -is [char] -or $Value.GetType().IsPrimitive -or $Value -is [decimal]) {
    return $Value
  }
  if ($Value -is [Collections.IDictionary]) {
    $out = [ordered]@{}
    foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
      $out[$key] = ConvertTo-MIRCPCanonicalValue -Value $Value[$key]
    }
    return $out
  }
  if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    $items = @($Value | ForEach-Object { ConvertTo-MIRCPCanonicalValue -Value $_ })
    Write-Output -NoEnumerate $items
    return
  }
  $record = [ordered]@{}
  foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
    $record[$property.Name] = ConvertTo-MIRCPCanonicalValue -Value $property.Value
  }
  return $record
}

function ConvertTo-MIRCPCanonicalJson {
  param([Parameter(Mandatory)]$Value)
  return (ConvertTo-MIRCPCanonicalValue -Value $Value | ConvertTo-Json -Depth 100 -Compress)
}

function Get-MIRCPSha256Text {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "")
  } finally {
    $sha.Dispose()
  }
}

function Get-MIRCPSha256Object {
  param([Parameter(Mandatory)]$Value)
  return Get-MIRCPSha256Text -Value (ConvertTo-MIRCPCanonicalJson -Value $Value)
}

function Get-MIRCPSha256File {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found for SHA-256: $Path" }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-MIRCPPortableTextSha256 {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found for portable text SHA-256: $Path" }
  $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
  return Get-MIRCPSha256Text -Value $text
}

function Write-MIRCPJson {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Value,
    [string]$RepoRoot = "",
    [switch]$Check
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $Path = Resolve-MIRCPPathToken -Path $Path -RepoRoot $repo
  $resolved = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
  $content = ((ConvertTo-MIRCPCanonicalValue -Value $Value | ConvertTo-Json -Depth 100) + "`n").Replace("`r`n", "`n")
  if ($Check) {
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Generated JSON is missing: $Path" }
    $existing = (Get-Content -Raw -LiteralPath $resolved).Replace("`r`n", "`n")
    if ($existing -cne $content) { throw "Generated JSON is stale: $Path" }
    return
  }
  $parent = Split-Path -Parent $resolved
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    [void](New-Item -ItemType Directory -Force -Path $parent)
  }
  [IO.File]::WriteAllText($resolved, $content, [Text.UTF8Encoding]::new($false))
}

function Get-MIRCPRelativePath {
  param(
    [Parameter(Mandatory)][string]$Path,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repo $Path)) }
  return [IO.Path]::GetRelativePath($repo, $full).Replace("\", "/")
}
