param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OfficialSpdxSchemaPath
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/SupplyChain.ps1')

function Assert-MIR4SupplyChainTest {
  param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Diagnostic)
  if (-not $Condition) { throw "[$Diagnostic]" }
}

function Assert-MIR4SupplyChainThrows {
  param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Diagnostic)
  $threw = $false
  try { & $Action } catch { $threw = $true }
  if (-not $threw) { throw "[$Diagnostic]" }
}

$authority = Get-MIR4SupplyChainAuthority -RepoRoot $repo
Assert-MIR4SupplyChainTest (@($authority.components).Count -eq 9) 'mir4-supply-chain-component-count'
Assert-MIR4SupplyChainTest (
  @($authority.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0
) 'mir4-supply-chain-transition-firewall'
Assert-MIR4SupplyChainTest (
  -not [bool]$authority.attestation.production_key_generation_authorized
) 'mir4-supply-chain-production-key-firewall'
Assert-MIR4SupplyChainTest (
  [int]$authority.runner_action_security.maximum_heavy_parallelism -eq 1 -and
  [int]$authority.runner_action_security.maximum_lightweight_parallelism -eq 2 -and
  [bool]$authority.runner_action_security.direct_dispatch_input_shell_interpolation_forbidden -and
  [bool]$authority.runner_action_security.publisher_admission_required
) 'mir4-supply-chain-runner-publisher-policy'
Assert-MIR4SupplyChainTest (
  @($authority.components | Where-Object {
    [string]$_.license.declared -cne 'MPL-2.0' -or
    [string]$_.license.concluded -cne 'NOASSERTION' -or
    [string]$_.copyright.text -cne 'NOASSERTION' -or
    [bool]$_.redistribution_custody.'separate-rights-grant_asserted'
  }).Count -eq 0
) 'mir4-supply-chain-rights-no-invention'

$orderRows = @(
  [pscustomobject]@{ path = 'a.txt'; bytes = 1; sha256 = ('A' * 64); source_class = 'manual-source'; origin = 'provided' },
  [pscustomobject]@{ path = 'b.bin'; bytes = 2; sha256 = ('B' * 64); source_class = 'binary-asset'; origin = 'provided' }
)
$rootA = Get-MIR4SupplyChainRowsRoot -Rows $orderRows
$rootB = Get-MIR4SupplyChainRowsRoot -Rows @($orderRows[1], $orderRows[0])
Assert-MIR4SupplyChainTest ([string]$rootA.sha256 -ceq [string]$rootB.sha256) 'mir4-supply-chain-root-order'
Assert-MIR4SupplyChainThrows {
  Get-MIR4SupplyChainRowsRoot -Rows @($orderRows[0], $orderRows[0]) | Out-Null
} 'mir4-supply-chain-root-duplicate'
Assert-MIR4SupplyChainThrows {
  ConvertTo-MIR4SupplyChainFileRow -Row ([pscustomobject]@{
    path = '../escape'; bytes = 1; sha256 = ('A' * 64)
  }) | Out-Null
} 'mir4-supply-chain-path-traversal'

$startingLocation = Get-Location
try {
  Set-Location -LiteralPath (Split-Path -Parent $repo)
  $relativeInput = Resolve-MIR4SupplyChainInputPath -RepoRoot $repo -Path 'LICENSE'
} finally {
  Set-Location -LiteralPath $startingLocation.Path
}
Assert-MIR4SupplyChainTest (
  $relativeInput -ceq (Resolve-Path -LiteralPath (Join-Path $repo 'LICENSE')).Path
) 'mir4-supply-chain-repo-relative-input'

$inventoryA = New-MIR4ComponentInventoryV1 -RepoRoot $repo
$inventoryB = New-MIR4ComponentInventoryV1 -RepoRoot $repo
Assert-MIR4SupplyChainTest (
  (Test-MIR4ComponentInventoryV1 -Inventory $inventoryA -RepoRoot $repo)
) 'mir4-supply-chain-inventory-a'
Assert-MIR4SupplyChainTest (
  (Test-MIR4ComponentInventoryV1 -Inventory $inventoryB -RepoRoot $repo)
) 'mir4-supply-chain-inventory-b'
Assert-MIR4SupplyChainTest (
  [string]$inventoryA.record_sha256 -ceq [string]$inventoryB.record_sha256
) 'mir4-supply-chain-inventory-determinism'
Assert-MIR4SupplyChainTest (
  @($inventoryA.identity_sets).Count -eq 3 -and
  @($inventoryA.components | Where-Object { [string]$_.materialization -ceq 'source-closure' }).Count -eq 9
) 'mir4-supply-chain-pre-freeze-source-closure'
$inventoryB = $null

$spdx301 = New-MIR4Spdx301Document -Inventory $inventoryA
Assert-MIR4SupplyChainTest (
  (Test-MIR4Spdx301Document -Document $spdx301 -Inventory $inventoryA -RepoRoot $repo -OfficialSchemaPath $OfficialSpdxSchemaPath)
) 'mir4-supply-chain-spdx-3.0.1'
$spdx23 = New-MIR4Spdx23CompatibilityDocument -Inventory $inventoryA
Assert-MIR4SupplyChainTest (
  (Test-MIR4Spdx23CompatibilityDocument -Document $spdx23 -RepoRoot $repo)
) 'mir4-supply-chain-spdx-2.3'
$slsa = New-MIR4SlsaProvenanceV1 -Inventory $inventoryA
Assert-MIR4SupplyChainTest (
  (Test-MIR4SlsaProvenanceV1 -Statement $slsa -RepoRoot $repo)
) 'mir4-supply-chain-slsa'

$slsaNegative = (ConvertTo-MIR4BootstrapCanonicalJson -Value $slsa) | ConvertFrom-Json -Depth 100 -DateKind String
$slsaNegative.predicate.buildDefinition.internalParameters.network = 'enabled'
Assert-MIR4SupplyChainTest (
  -not (Test-MIR4SlsaProvenanceV1 -Statement $slsaNegative -RepoRoot $repo)
) 'mir4-supply-chain-slsa-network-negative'
$inventoryNegative = (ConvertTo-MIR4BootstrapCanonicalJson -Value $inventoryA) | ConvertFrom-Json -Depth 100 -DateKind String
$inventoryNegative.components[0].files[0].sha256 = '0' * 64
Assert-MIR4SupplyChainTest (
  -not (Test-MIR4ComponentInventoryV1 -Inventory $inventoryNegative)
) 'mir4-supply-chain-inventory-tamper-negative'

$projectionText = (ConvertTo-MIR4BootstrapCanonicalJson -Value $spdx301) +
  (ConvertTo-MIR4BootstrapCanonicalJson -Value $spdx23) +
  (ConvertTo-MIR4BootstrapCanonicalJson -Value $slsa)
Assert-MIR4SupplyChainTest (
  $projectionText -cnotmatch '(?i)(?:[A-Z]:\\|C:/Users/|D:/|private[_-]?key|passphrase|mod[_-]?portal[_-]?token)'
) 'mir4-supply-chain-public-path-secret-leak'
$packageFingerprint = Get-MIRPackageSourceFingerprint -RepoRoot $repo
Assert-MIR4SupplyChainTest (
  $packageFingerprint -ceq 'F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E'
) 'mir4-supply-chain-package-non-interference'

[pscustomobject][ordered]@{
  status = 'passed'
  components = @($inventoryA.components).Count
  inventory_root = [string]$inventoryA.record_sha256
  spdx301_graph_elements = @($spdx301.'@graph').Count
  spdx23_files = @($spdx23.files).Count
  provenance_subjects = @($slsa.subject).Count
  official_spdx_schema = $(if ([string]::IsNullOrWhiteSpace($OfficialSpdxSchemaPath)) { 'not-supplied' } else { 'bounded-validated' })
  package_source_sha256 = $packageFingerprint
  transition_authority = 'unchanged'
}
