. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')

$script:MIR4RuntimeContinuityMigrationReceiptPath='releases/migrations/MIR4-Runtime-Continuity-Tooling-MigrationV1.json'
$script:MIR4RuntimeContinuityMigrationReceiptSchemaPath='contracts/repository/mir4-runtime-continuity-migration-receipt-v1.schema.json'
$script:MIR4RuntimeContinuityMigrationReceiptSha256='731091D00E0ABA7E7E07E736E0C5299D45FAE588421A953E401310B2ACCBDC78'
$script:MIR4RuntimeContinuityMigrationReceiptBytes=44462

function Get-MIR4RuntimeContinuityMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $receipt=Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo `
    -ReceiptPath $script:MIR4RuntimeContinuityMigrationReceiptPath `
    -ExpectedSha256 $script:MIR4RuntimeContinuityMigrationReceiptSha256 `
    -SchemaPath $script:MIR4RuntimeContinuityMigrationReceiptSchemaPath `
    -Kind 'MIR4RuntimeContinuityMigrationReceiptV1' `
    -DigestDomain 'mir4:runtime-continuity-migration-receipt:1' `
    -ErrorPrefix 'mir4-runtime-continuity-migration'
  if((Get-Item -LiteralPath (Join-Path $repo $script:MIR4RuntimeContinuityMigrationReceiptPath)).Length-ne$script:MIR4RuntimeContinuityMigrationReceiptBytes){throw '[mir4-runtime-continuity-migration-receipt-byte-length]'}
  return $receipt
}

function Invoke-MIR4RuntimeContinuityMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  if(-not$Check){throw '[mir4-runtime-continuity-migration-receipt-immutable] generation-disabled-after-successor-cutover'}
  return Get-MIR4RuntimeContinuityMigrationReceiptV1 -RepoRoot $RepoRoot
}
