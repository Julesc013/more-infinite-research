. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')

$script:MIR4ProcessIRExactMigrationReceiptPath='releases/migrations/MIR4-ProcessIR-Exact-Tooling-MigrationV1.json'
$script:MIR4ProcessIRExactMigrationReceiptSchemaPath='contracts/repository/mir4-processir-exact-migration-receipt-v1.schema.json'
$script:MIR4ProcessIRExactMigrationReceiptSha256='163714759F02DEFC8D6301923CC6796F1382D1ABF3841712FC87F4C9FEEACE8E'
$script:MIR4ProcessIRExactMigrationReceiptBytes=48215

function Get-MIR4ProcessIRExactMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $receipt=Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo -ReceiptPath $script:MIR4ProcessIRExactMigrationReceiptPath -ExpectedSha256 $script:MIR4ProcessIRExactMigrationReceiptSha256 -SchemaPath $script:MIR4ProcessIRExactMigrationReceiptSchemaPath -Kind 'MIR4ProcessIRExactMigrationReceiptV1' -DigestDomain 'mir4:processir-exact-migration-receipt:1' -ErrorPrefix 'mir4-processir-exact-migration'
  if((Get-Item -LiteralPath (Join-Path $repo $script:MIR4ProcessIRExactMigrationReceiptPath)).Length-ne$script:MIR4ProcessIRExactMigrationReceiptBytes){throw '[mir4-processir-exact-migration-receipt-byte-length]'}
  return $receipt
}

function Invoke-MIR4ProcessIRExactMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  if(-not$Check){throw '[mir4-processir-exact-migration-receipt-immutable] generation-disabled-after-successor-cutover'}
  return Get-MIR4ProcessIRExactMigrationReceiptV1 -RepoRoot $RepoRoot
}
