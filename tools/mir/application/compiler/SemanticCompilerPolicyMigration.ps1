. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')

$script:MIR4SemanticCompilerPolicyMigrationReceiptPath='releases/migrations/MIR4-Semantic-Compiler-Policy-Tooling-MigrationV1.json'
$script:MIR4SemanticCompilerPolicyMigrationReceiptSchemaPath='contracts/repository/mir4-semantic-compiler-policy-migration-receipt-v1.schema.json'
$script:MIR4SemanticCompilerPolicyMigrationReceiptSha256='A1F7B204B839C6425D37EDB34208B0F37FBEA0DC40E1FE45658CED78DC53C5C9'
$script:MIR4SemanticCompilerPolicyMigrationReceiptBytes=46342

function Get-MIR4SemanticCompilerPolicyMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $receipt=Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo `
    -ReceiptPath $script:MIR4SemanticCompilerPolicyMigrationReceiptPath `
    -ExpectedSha256 $script:MIR4SemanticCompilerPolicyMigrationReceiptSha256 `
    -SchemaPath $script:MIR4SemanticCompilerPolicyMigrationReceiptSchemaPath `
    -Kind 'MIR4SemanticCompilerPolicyMigrationReceiptV1' `
    -DigestDomain 'mir4:semantic-compiler-policy-migration-receipt:1' `
    -ErrorPrefix 'mir4-semantic-compiler-policy-migration'
  if((Get-Item -LiteralPath (Join-Path $repo $script:MIR4SemanticCompilerPolicyMigrationReceiptPath)).Length-ne$script:MIR4SemanticCompilerPolicyMigrationReceiptBytes){throw '[mir4-semantic-compiler-policy-migration-receipt-byte-length]'}
  return $receipt
}

function Invoke-MIR4SemanticCompilerPolicyMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  if(-not$Check){throw '[mir4-semantic-compiler-policy-migration-receipt-immutable] generation-disabled-after-successor-cutover'}
  return Get-MIR4SemanticCompilerPolicyMigrationReceiptV1 -RepoRoot $RepoRoot
}
