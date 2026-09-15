[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$RecordedAt = '',
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path } else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PackagePresentation.ps1')

if (-not [string]::IsNullOrWhiteSpace($RecordedAt)) {
  throw '[mir4-package-presentation-v2-authority-immutable-overwrite]'
}

# V2 is an immutable M41 receipt. This retained command verifies custody only;
# V3 is the append-only current source/composition presentation authority.
$v2 = Get-MIR4CurrentPackagePresentationV2 -RepoRoot $RepoRoot
$evolutionPath = Join-Path $RepoRoot 'spec/distribution/mir4-current-package-presentation-v2-evolution-receipt.json'
$evolutionRaw = Get-Content -Raw -LiteralPath $evolutionPath
if (-not ($evolutionRaw | Test-Json -SchemaFile (Join-Path $RepoRoot 'contracts/repository/mir4-current-package-presentation-v2-evolution-receipt.schema.json'))) {
  throw '[mir4-package-presentation-v2-evolution-schema]'
}
$evolution = $evolutionRaw | ConvertFrom-Json -Depth 100 -DateKind String
if (-not (Test-MIR4BootstrapRecordHash -Record $evolution) -or
    [string]$v2.record_sha256 -cne 'C33F1B568CA247108D88C4F2A109C45E29F2C77C4EE026CB4C9047BAA3A2360F' -or
    [string]$evolution.authority.path -cne 'spec/distribution/mir4-current-package-presentation-v2.json' -or
    [string]$evolution.authority.record_sha256 -cne [string]$v2.record_sha256 -or
    [bool]$evolution.transition_gate.version_allocation -or
    [bool]$evolution.transition_gate.publication) {
  throw '[mir4-package-presentation-v2-historical-custody]'
}
return [pscustomobject][ordered]@{
  status = 'passed-frozen-package-presentation-v2-verification'
  classification = 'historical-verification-only'
  authority_path = 'spec/distribution/mir4-current-package-presentation-v2.json'
  record_sha256 = [string]$v2.record_sha256
  current_successor = 'spec/distribution/mir4-current-package-presentation-v3.json'
  player_package_mutation_authorized = $false
  publication_authorized = $false
}
