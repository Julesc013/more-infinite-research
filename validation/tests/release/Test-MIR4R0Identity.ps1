param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $RepoRoot "tools/lib/validation/MIR4DistributionIdentity.ps1")

$result = Assert-MIR4R0DistributionIdentity -RepoRoot $RepoRoot
Write-Host "[ok] MIR 4 R0 V2 distribution identity: $($result.public_target_count) targets, $($result.public_vector_count) public vectors, $($result.negative_vector_count) negative vectors"
