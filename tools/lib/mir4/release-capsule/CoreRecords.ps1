function Get-MIR4ReleaseCapsuleRepoRootV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Write-MIR4ReleaseCapsuleRecordV1 {
  param(
    [Parameter(Mandatory)]$Record,
    [Parameter(Mandatory)][string]$Path,
    [switch]$AppendOnly
  )

  $text = (ConvertTo-MIR4BootstrapCanonicalJson -Value $Record) + [char]10
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  if ($AppendOnly -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
    $existing = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
    if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$existing, [byte[]]$bytes)) {
      throw "[mir4-release-capsule-append-only-conflict] $Path"
    }
    return
  }
  [IO.File]::WriteAllBytes($Path, $bytes)
}

function Read-MIR4ReleaseCapsuleJsonV1 {
  param(
    [Parameter(Mandatory)][string]$Path,
    [ValidateRange(1, 134217728)][long]$MaximumBytes = 16777216
  )

  $item = Get-Item -LiteralPath (Resolve-Path -LiteralPath $Path).Path
  if ([long]$item.Length -gt $MaximumBytes) {
    throw "[mir4-release-capsule-json-bounds] $Path"
  }
  $utf8 = [Text.UTF8Encoding]::new($false, $true)
  return $utf8.GetString([IO.File]::ReadAllBytes($item.FullName)) |
    ConvertFrom-Json -Depth 100 -DateKind String
}

function Get-MIR4ReleaseCapsuleObjectPathV1 {
  param([Parameter(Mandatory)][string]$Sha256)
  $digest = $Sha256.ToUpperInvariant()
  if ($digest -cnotmatch '^[0-9A-F]{64}$') {
    throw '[mir4-release-capsule-object-digest]'
  }
  return "objects/sha256/$($digest.Substring(0, 2))/$digest"
}

function Get-MIR4ReleaseCapsuleStreamSha256V1 {
  param([Parameter(Mandatory)][IO.Stream]$Stream)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    return [Convert]::ToHexString($sha.ComputeHash($Stream))
  } finally {
    $sha.Dispose()
  }
}
