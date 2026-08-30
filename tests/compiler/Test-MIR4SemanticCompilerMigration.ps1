param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/compiler/SemanticCompilerPolicyMigration.ps1')

$receipt=Invoke-MIR4SemanticCompilerPolicyMigrationProjectionV1 -RepoRoot $repo -Check
if([string]$receipt.migration_id-cne'MIR4-SEMANTIC-COMPILER-POLICY-TOOLING-V1'){throw '[mir4-semantic-compiler-policy-migration-historical-id]'}
if((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4SemanticCompilerPolicyMigrationReceiptPath) -Algorithm SHA256).Hash-cne$script:MIR4SemanticCompilerPolicyMigrationReceiptSha256){throw '[mir4-semantic-compiler-policy-migration-historical-bytes]'}
try{Invoke-MIR4SemanticCompilerPolicyMigrationProjectionV1 -RepoRoot $repo|Out-Null;throw '[mir4-semantic-compiler-policy-migration-historical-write-enabled]'}
catch{if(-not$_.Exception.Message.StartsWith('[mir4-semantic-compiler-policy-migration-receipt-immutable]')){throw}}

$checkOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4SemanticCompilerPolicyMigration.ps1') -Command check -RepoRoot $repo 2>&1|Out-String).Trim()
if($LASTEXITCODE-ne0){throw "[mir4-semantic-compiler-policy-migration-historical-cli-check] $checkOutput"}
$showOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4SemanticCompilerPolicyMigration.ps1') -Command show -RepoRoot $repo 2>&1|Out-String).Trim()
if($LASTEXITCODE-ne0-or$checkOutput-cne$showOutput){throw '[mir4-semantic-compiler-policy-migration-historical-cli-parity]'}
$generateOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4SemanticCompilerPolicyMigration.ps1') -Command generate -RepoRoot $repo 2>&1|Out-String).Trim()
if($LASTEXITCODE-eq0-or$generateOutput-notmatch'mir4-semantic-compiler-policy-migration-receipt-immutable'){throw '[mir4-semantic-compiler-policy-migration-historical-cli-write-enabled]'}
$global:LASTEXITCODE=0

[pscustomobject][ordered]@{status='accepted-immutable-historical-receipt';migration_id=[string]$receipt.migration_id;raw_sha256=$script:MIR4SemanticCompilerPolicyMigrationReceiptSha256;byte_length=$script:MIR4SemanticCompilerPolicyMigrationReceiptBytes;writer_enabled=$false;release_transition_authority=$false}
