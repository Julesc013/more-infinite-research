. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot 'WholePlatform.ps1')

$script:MIR4WholePlatformMigrationAuthorityPath = 'governance/repository/migrations/whole-platform-tooling-v1.json'
$script:MIR4WholePlatformMigrationAuthoritySchemaPath = 'contracts/repository/mir4-whole-platform-migration-authority-v1.schema.json'
$script:MIR4WholePlatformMigrationProofPath = 'assurance/repository/whole-platform-tooling-v1.json'
$script:MIR4WholePlatformMigrationProofSchemaPath = 'contracts/repository/mir4-whole-platform-migration-proof-v1.schema.json'
$script:MIR4WholePlatformMigrationReceiptPath = 'releases/migrations/MIR4-Whole-Platform-Tooling-MigrationV1.json'
$script:MIR4WholePlatformMigrationReceiptSchemaPath = 'contracts/repository/mir4-whole-platform-migration-receipt-v1.schema.json'
$script:MIR4WholePlatformMigrationReceiptSha256 = '4DEFD2256070F627031AC39FB244619E5E7E1949061DED5F89CF438D810F4B78'
$script:MIR4WholePlatformPredecessorReceiptPath = 'releases/migrations/MIR4-Target-Key-Tooling-MigrationV1.json'
$script:MIR4WholePlatformPredecessorReceiptSha256 = '79E3ECC14FDC354A3F2509F4AC3366E790547F6E606B2F65096E7CFD5866C06D'
$script:MIR4WholePlatformParityDigestV1 = 'sha256:50eb0da4637175c4257904a29d58a45e39f9898d5fb67e92f10fcf73e541b46a'

function Get-MIR4WholePlatformMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4WholePlatformMigrationAuthorityPath -SchemaPath $script:MIR4WholePlatformMigrationAuthoritySchemaPath)) {
    throw '[mir4-whole-platform-migration-authority-schema]'
  }
  $authority = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4WholePlatformMigrationAuthorityPath
  if ([string]$authority.predecessor_receipt.path -cne $script:MIR4WholePlatformPredecessorReceiptPath -or
      [string]$authority.predecessor_receipt.sha256 -cne $script:MIR4WholePlatformPredecessorReceiptSha256) {
    throw '[mir4-whole-platform-migration-predecessor-authority]'
  }
  if (@($authority.writers).Count -ne 1 -or [string]$authority.writers[0].path -cne 'tools/mir/application/platform/WholePlatformMigration.ps1') {
    throw '[mir4-whole-platform-migration-single-writer]'
  }
  $finalPaths = @($authority.path_map | ForEach-Object { [string]$_.final_path })
  if (@($finalPaths | Sort-Object -Unique).Count -ne $finalPaths.Count) { throw '[mir4-whole-platform-migration-duplicate-final-path]' }
  if (@($authority.release_transition_authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
    throw '[mir4-whole-platform-migration-release-authority]'
  }
  return $authority
}

function Get-MIR4WholePlatformMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4WholePlatformMigrationProofPath -SchemaPath $script:MIR4WholePlatformMigrationProofSchemaPath)) {
    throw '[mir4-whole-platform-migration-proof-schema]'
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4WholePlatformMigrationProofPath
}

function Test-MIR4WholePlatformCompatibilityForwardersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $libraryPath = 'tools/lib/mir4/WholePlatform.ps1'
  $libraryText = [IO.File]::ReadAllText((Join-Path $repo $libraryPath)).Replace('\','/')
  if ($libraryText -cnotmatch 'MIR4-WHOLE-PLATFORM-COMPATIBILITY-LIBRARY' -or
      $libraryText -cnotmatch [regex]::Escape('mir/application/platform/WholePlatform.ps1') -or
      $libraryText.Split([char]10).Count -gt 4) {
    throw "[mir4-whole-platform-compatibility-forwarder] $libraryPath"
  }
  $testPath = 'validation/tests/mir4/Test-MIR4WholePlatform.ps1'
  $testText = [IO.File]::ReadAllText((Join-Path $repo $testPath)).Replace('\','/')
  if ($testText -cnotmatch 'MIR4-WHOLE-PLATFORM-COMPATIBILITY-TEST' -or
      $testText -cnotmatch [regex]::Escape('tests/platform/Test-MIR4WholePlatform.ps1') -or
      $testText.Split([char]10).Count -gt 5) {
    throw "[mir4-whole-platform-compatibility-forwarder] $testPath"
  }
  return $true
}

function Test-MIR4WholePlatformDeclaredConsumersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $bindings = [ordered]@{
    'tools/commands/mir4/Invoke-MIR4WholePlatform.ps1' = 'tools/mir/application/platform/WholePlatform.ps1'
    'tests/platform/Test-MIR4WholePlatform.ps1' = 'tools/mir/application/platform/WholePlatform.ps1'
    'tools/lib/mir4/PlatformPreview.ps1' = 'tools/mir/application/platform/WholePlatform.ps1'
    '.mir/modules.yml' = 'tools/mir/application/platform/WholePlatform.ps1'
  }
  foreach ($entry in $bindings.GetEnumerator()) {
    $text = [IO.File]::ReadAllText((Join-Path $repo ([string]$entry.Key))).Replace('\','/')
    if ($text -cnotmatch [regex]::Escape([string]$entry.Value)) {
      throw "[mir4-whole-platform-consumer-final-path] $($entry.Key)"
    }
  }
  return $true
}

function Get-MIR4WholePlatformFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $matrix = Get-MIR4WholePlatformMatrix -RepoRoot $repo
  $markdown = ConvertTo-MIR4WholePlatformMarkdown -Matrix $matrix
  $markdownSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($markdown)))
  $record = [ordered]@{
    matrix=$matrix
    generated_markdown_sha256=$markdownSha256
  }
  return [pscustomobject][ordered]@{
    record=$record
    digest=(Get-MIR4CanonicalDigestV1 -Value $record -Domain 'mir4:whole-platform-functional-parity:1')
  }
}

function Test-MIR4WholePlatformFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $result = Get-MIR4WholePlatformFunctionalParityV1 -RepoRoot $RepoRoot
  $matrix = $result.record.matrix
  if ([int]$matrix.area_count -ne 18 -or [int]$matrix.executable_area_count -ne 18 -or [int]$matrix.later_release_area_count -ne 0) {
    throw '[mir4-whole-platform-functional-shape-parity]'
  }
  if ((@($matrix.target_key_examples) -join '|') -cne 'F210|F200|F018|F006') {
    throw '[mir4-whole-platform-target-example-parity]'
  }
  if ([string]$result.record.generated_markdown_sha256 -cne '0AF6DBCABC2396D0D2292FA6FA4C749CF3D4036D6ACF9914F2C7B1812C6924F8') {
    throw '[mir4-whole-platform-markdown-parity]'
  }
  if ([string]$result.digest -cne $script:MIR4WholePlatformParityDigestV1) { throw '[mir4-whole-platform-functional-parity]' }
  return $result
}

function New-MIR4WholePlatformMigrationReceiptV1 {
  throw '[mir4-whole-platform-migration-receipt-immutable]'
}

function Get-MIR4WholePlatformMigrationReceiptTextV1 {
  throw '[mir4-whole-platform-migration-receipt-immutable]'
}

function Test-MIR4WholePlatformHistoricalMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $RepoRoot `
    -ReceiptPath $script:MIR4WholePlatformMigrationReceiptPath `
    -ExpectedSha256 $script:MIR4WholePlatformMigrationReceiptSha256 `
    -SchemaPath $script:MIR4WholePlatformMigrationReceiptSchemaPath `
    -Kind 'MIR4WholePlatformMigrationReceiptV1' `
    -DigestDomain 'mir4:whole-platform-migration-receipt:1' `
    -ErrorPrefix 'mir4-whole-platform-migration'
}

function Invoke-MIR4WholePlatformMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  if(-not$Check){throw '[mir4-whole-platform-migration-receipt-immutable]'}
  return Test-MIR4WholePlatformHistoricalMigrationReceiptV1 -RepoRoot $RepoRoot
}
