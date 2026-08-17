param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $RepoRoot "tools/lib/validation/MIR4DistributionIdentity.ps1")

$result = Assert-MIR4R0DistributionIdentity -RepoRoot $RepoRoot
$registryV2Path = Join-Path $RepoRoot ".mir/releases/waves/mir4-r0/MIR4-Target-RegistryV2.json"
$registryV3Path = Join-Path $RepoRoot ".mir/releases/waves/mir4-r0/MIR4-Target-RegistryV3.json"
$registryV4Path = Join-Path $RepoRoot ".mir/releases/waves/mir4-r0/MIR4-Target-RegistryV4.json"
$registryV4SchemaPath = Join-Path $RepoRoot "spec/schemas/mir4-target-registry-v4.schema.json"
$registryV2 = Get-Content -Raw -LiteralPath $registryV2Path | ConvertFrom-Json -Depth 100
$registryV3 = Get-Content -Raw -LiteralPath $registryV3Path | ConvertFrom-Json -Depth 100
$registryV4Text = Get-Content -Raw -LiteralPath $registryV4Path
$registryV4 = $registryV4Text | ConvertFrom-Json -Depth 100
if (-not ($registryV4Text | Test-Json -SchemaFile $registryV4SchemaPath -ErrorAction Stop)) {
  throw "MIR 4 Target Registry V4 schema validation failed."
}
if ((@($registryV4.imports) -join "|") -ne ".mir/targets.json|.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV3.json|.mir/releases/waves/mir4-r0/MIR4-Terminal-Predecessor-RefreshV3.json|.mir/releases/waves/mir4-r0/MIR4-Terminal-Import-CompositeV3.json") {
  throw "MIR 4 Target Registry V4 does not bind the append-only V3 predecessor refresh."
}
for ($index = 0; $index -lt @($registryV3.payload.targets).Count; $index++) {
  $historical = $registryV3.payload.targets[$index]
  $current = $registryV4.payload.targets[$index]
  if ([string]$historical.id -cne [string]$current.id -or
      [string]$historical.distribution_target_code -cne [string]$current.distribution_target_code) {
    throw "MIR 4 Target Registry V4 changed target identity or distribution code at index $index."
  }
}
$f210 = @($registryV4.payload.targets | Where-Object id -eq "factorio-2.1")
$f200 = @($registryV4.payload.targets | Where-Object id -eq "factorio-2.0")
if ($f210.Count -ne 1 -or [string]$f210[0].mir3_predecessor -cne "3.2.11" -or
    $f200.Count -ne 1 -or [string]$f200[0].mir3_predecessor -cne "2.5.11") {
  throw "MIR 4 Target Registry V4 does not bind the exact current MIR 3 predecessors."
}
Write-Host "[ok] MIR 4 R0 V2 codec and V4 predecessor identity: $($result.public_target_count) targets, $($result.public_vector_count) public vectors, $($result.negative_vector_count) negative vectors"
