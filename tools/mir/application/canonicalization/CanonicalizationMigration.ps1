. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')

$script:MIR4CanonicalizationMigrationAuthorityPath = 'governance/repository/migrations/canonicalization-tooling-v1.json'
$script:MIR4CanonicalizationMigrationAuthoritySchemaPath = 'contracts/repository/mir4-canonicalization-migration-authority-v1.schema.json'
$script:MIR4CanonicalizationMigrationProofPath = 'assurance/repository/canonicalization-tooling-v1.json'
$script:MIR4CanonicalizationMigrationProofSchemaPath = 'contracts/repository/mir4-canonicalization-migration-proof-v1.schema.json'
$script:MIR4CanonicalizationMigrationReceiptPath = 'releases/migrations/MIR4-Canonicalization-Tooling-MigrationV1.json'
$script:MIR4CanonicalizationMigrationReceiptSchemaPath = 'contracts/repository/mir4-canonicalization-migration-receipt-v1.schema.json'
$script:MIR4CanonicalizationMigrationReceiptSha256 = 'B126E835EDE63832D62833B4A96FD888301DB608858A1D94BC2D4B93F7ADA27A'
$script:MIR4CanonicalizationPredecessorReceiptPath = 'releases/migrations/MIR4-Repository-Fixed-Point-Tooling-MigrationV1.json'
$script:MIR4CanonicalizationPredecessorReceiptSha256 = '5B188181285DB7F89E6F0CA91221F9028EEDF212CA62D5BEC2A56D59D3510D26'

function Get-MIR4CanonicalizationMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4CanonicalizationMigrationAuthorityPath -SchemaPath $script:MIR4CanonicalizationMigrationAuthoritySchemaPath)) {
    throw '[mir4-canonicalization-migration-authority-schema]'
  }
  $authority = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4CanonicalizationMigrationAuthorityPath
  if ([string]$authority.predecessor_receipt.path -cne $script:MIR4CanonicalizationPredecessorReceiptPath -or
      [string]$authority.predecessor_receipt.sha256 -cne $script:MIR4CanonicalizationPredecessorReceiptSha256) {
    throw '[mir4-canonicalization-migration-predecessor-authority]'
  }
  if (@($authority.writers).Count -ne 1 -or [string]$authority.writers[0].path -cne 'tools/mir/application/canonicalization/CanonicalizationMigration.ps1') {
    throw '[mir4-canonicalization-migration-single-writer]'
  }
  $finalPaths = @($authority.path_map | ForEach-Object { [string]$_.final_path })
  if (@($finalPaths | Sort-Object -Unique).Count -ne $finalPaths.Count) { throw '[mir4-canonicalization-migration-duplicate-final-path]' }
  if (@($authority.release_transition_authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
    throw '[mir4-canonicalization-migration-release-authority]'
  }
  return $authority
}

function Get-MIR4CanonicalizationMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4CanonicalizationMigrationProofPath -SchemaPath $script:MIR4CanonicalizationMigrationProofSchemaPath)) {
    throw '[mir4-canonicalization-migration-proof-schema]'
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4CanonicalizationMigrationProofPath
}

function Test-MIR4CanonicalizationCompatibilityForwardersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $contracts = @(
    [ordered]@{path='tools/lib/mir4/CanonicalJsonV1.ps1';marker='MIR4-CANONICALIZATION-COMPATIBILITY-LIBRARY';target='mir/domain/canonicalization/CanonicalJsonV1.ps1';max_lines=5},
    [ordered]@{path='validation/tests/mir4/Test-MIR4CanonicalizationDiagnosticsT07.ps1';marker='MIR4-CANONICALIZATION-COMPATIBILITY-TEST';target='tests/canonicalization/Test-MIR4CanonicalizationDiagnostics.ps1';max_lines=6}
  )
  foreach ($contract in $contracts) {
    $text = [IO.File]::ReadAllText((Join-Path $repo ([string]$contract.path)))
    if ($text -cnotmatch [regex]::Escape([string]$contract.marker) -or
        $text.Replace('\','/') -cnotmatch [regex]::Escape([string]$contract.target) -or
        $text.Split([char]10).Count -gt [int]$contract.max_lines) {
      throw "[mir4-canonicalization-compatibility-forwarder] $($contract.path)"
    }
  }
  return $true
}

function Test-MIR4CanonicalizationHistoricalMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $RepoRoot `
    -ReceiptPath $script:MIR4CanonicalizationMigrationReceiptPath `
    -ExpectedSha256 $script:MIR4CanonicalizationMigrationReceiptSha256 `
    -SchemaPath $script:MIR4CanonicalizationMigrationReceiptSchemaPath `
    -Kind 'MIR4CanonicalizationMigrationReceiptV1' `
    -DigestDomain 'mir4:canonicalization-migration-receipt:1' `
    -ErrorPrefix 'mir4-canonicalization-migration'
}

function New-MIR4CanonicalizationMigrationReceiptV1 {
  throw '[mir4-canonicalization-migration-receipt-immutable]'
}

function Get-MIR4CanonicalizationMigrationReceiptTextV1 {
  throw '[mir4-canonicalization-migration-receipt-immutable]'
}

function Invoke-MIR4CanonicalizationMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  if (-not $Check) { throw '[mir4-canonicalization-migration-receipt-immutable]' }
  return Test-MIR4CanonicalizationHistoricalMigrationReceiptV1 -RepoRoot $RepoRoot
}
