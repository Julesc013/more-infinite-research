. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')

$script:MIR4ModuleSdkMepMigrationReceiptPath='releases/migrations/MIR4-Module-Sdk-Mep-Tooling-MigrationV1.json'
$script:MIR4ModuleSdkMepMigrationReceiptSchemaPath='contracts/repository/mir4-module-sdk-mep-migration-receipt-v1.schema.json'
$script:MIR4ModuleSdkMepMigrationReceiptSha256='AFA11010DBAB95012433522BA99B1481D02709E0ACE50C8E6BDFCBC3D732C0FA'
$script:MIR4ModuleSdkMepMigrationReceiptBytes=55477

function Get-MIR4ModuleSdkMepMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $receipt=Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo -ReceiptPath $script:MIR4ModuleSdkMepMigrationReceiptPath -ExpectedSha256 $script:MIR4ModuleSdkMepMigrationReceiptSha256 -SchemaPath $script:MIR4ModuleSdkMepMigrationReceiptSchemaPath -Kind 'MIR4ModuleSdkMepMigrationReceiptV1' -DigestDomain 'mir4:module-sdk-mep-migration-receipt:1' -ErrorPrefix 'mir4-module-sdk-mep-migration'
  if((Get-Item -LiteralPath (Join-Path $repo $script:MIR4ModuleSdkMepMigrationReceiptPath)).Length-ne$script:MIR4ModuleSdkMepMigrationReceiptBytes){throw '[mir4-module-sdk-mep-migration-receipt-byte-length]'}
  return $receipt
}

function Invoke-MIR4ModuleSdkMepMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  if(-not$Check){throw '[mir4-module-sdk-mep-migration-receipt-immutable] generation-disabled-after-successor-cutover'}
  return Get-MIR4ModuleSdkMepMigrationReceiptV1 -RepoRoot $RepoRoot
}
