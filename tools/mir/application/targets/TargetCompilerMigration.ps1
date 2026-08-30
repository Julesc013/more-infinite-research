. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')

$script:MIR4TargetCompilerMigrationAuthorityPath='governance/repository/migrations/target-compiler-tooling-v1.json'
$script:MIR4TargetCompilerMigrationAuthoritySchemaPath='contracts/repository/mir4-target-compiler-migration-authority-v1.schema.json'
$script:MIR4TargetCompilerMigrationProofPath='assurance/repository/target-compiler-tooling-v1.json'
$script:MIR4TargetCompilerMigrationProofSchemaPath='contracts/repository/mir4-target-compiler-migration-proof-v1.schema.json'
$script:MIR4TargetCompilerMigrationReceiptPath='releases/migrations/MIR4-Target-Compiler-Tooling-MigrationV1.json'
$script:MIR4TargetCompilerMigrationReceiptSchemaPath='contracts/repository/mir4-target-compiler-migration-receipt-v1.schema.json'
$script:MIR4TargetCompilerMigrationReceiptSha256='799232DAFAF72E3A3B4862DFE19667D39BEAE2FAE6118B4F2228EB98A7E41EBC'

function New-MIR4TargetCompilerMigrationReceiptV1 {
  throw '[mir4-target-compiler-migration-receipt-immutable]'
}

function Get-MIR4TargetCompilerMigrationReceiptTextV1 {
  throw '[mir4-target-compiler-migration-receipt-immutable]'
}

function Test-MIR4TargetCompilerHistoricalMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $RepoRoot `
    -ReceiptPath $script:MIR4TargetCompilerMigrationReceiptPath `
    -ExpectedSha256 $script:MIR4TargetCompilerMigrationReceiptSha256 `
    -SchemaPath $script:MIR4TargetCompilerMigrationReceiptSchemaPath `
    -Kind 'MIR4TargetCompilerMigrationReceiptV1' `
    -DigestDomain 'mir4:target-compiler-migration-receipt:1' `
    -ErrorPrefix 'mir4-target-compiler-migration'
}

function Invoke-MIR4TargetCompilerMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  if(-not$Check){throw '[mir4-target-compiler-migration-receipt-immutable]'}
  return Test-MIR4TargetCompilerHistoricalMigrationReceiptV1 -RepoRoot $RepoRoot
}
