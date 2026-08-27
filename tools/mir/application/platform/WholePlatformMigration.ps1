. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot 'WholePlatform.ps1')

$script:MIR4WholePlatformMigrationAuthorityPath = 'governance/repository/migrations/whole-platform-tooling-v1.json'
$script:MIR4WholePlatformMigrationAuthoritySchemaPath = 'contracts/repository/mir4-whole-platform-migration-authority-v1.schema.json'
$script:MIR4WholePlatformMigrationProofPath = 'assurance/repository/whole-platform-tooling-v1.json'
$script:MIR4WholePlatformMigrationProofSchemaPath = 'contracts/repository/mir4-whole-platform-migration-proof-v1.schema.json'
$script:MIR4WholePlatformMigrationReceiptPath = 'releases/migrations/MIR4-Whole-Platform-Tooling-MigrationV1.json'
$script:MIR4WholePlatformMigrationReceiptSchemaPath = 'contracts/repository/mir4-whole-platform-migration-receipt-v1.schema.json'
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
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $migration = Get-MIR4WholePlatformMigrationAuthorityV1 -RepoRoot $repo
  $proof = Get-MIR4WholePlatformMigrationProofPolicyV1 -RepoRoot $repo
  $prior = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration
  [void](Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo -ReceiptPath $script:MIR4WholePlatformPredecessorReceiptPath `
    -ExpectedSha256 $script:MIR4WholePlatformPredecessorReceiptSha256 `
    -SchemaPath 'contracts/repository/mir4-target-key-migration-receipt-v1.schema.json' `
    -Kind 'MIR4TargetKeyMigrationReceiptV1' `
    -DigestDomain 'mir4:target-key-migration-receipt:1' `
    -ErrorPrefix 'mir4-whole-platform-predecessor')
  [void](Test-MIR4WholePlatformCompatibilityForwardersV1 -RepoRoot $repo)
  [void](Test-MIR4WholePlatformDeclaredConsumersV1 -RepoRoot $repo)
  [void](Test-MIR4WholePlatformFunctionalParityV1 -RepoRoot $repo)

  $integrationPaths = @(
    '.gitattributes',
    '.mir/assurance.json',
    '.mir/control/repository-fixed-point.json',
    '.mir/control/paths.yml',
    '.mir/control-plane/ownership.json',
    '.mir/modules.yml',
    '.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json',
    'validation/tests.yml',
    'tools/mir.ps1',
    'tools/lib/mir4/PreFreezeRelease.ps1',
    'tools/lib/mir4/PlatformPreview.ps1',
    'tools/commands/mir4/Invoke-MIR4WholePlatform.ps1',
    'tools/mir/domain/repository/RepositoryFixedPoint.ps1',
    'tools/mir/application/targets/TargetKeyMigration.ps1',
    'tools/mir/cli/Invoke-MIR4TargetKeyMigration.ps1',
    'tests/targets/Test-MIR4TargetKeyMigration.ps1',
    'tests/repository/Test-MIR4RepositoryFixedPoint.ps1',
    'docs/architecture/mir4-repository-fixed-point.md',
    'docs/architecture/module-boundaries.md',
    'docs/reference/generated/mir4-whole-platform-matrix.md',
    'mir.lock',
    'sdk/preview/mir4/reference/compilation-runs.json',
    'sdk/preview/mir4/reference/inspection-bundle-v1.json',
    'sdk/preview/mir4/reference/inspector-workbench-result-v1.json',
    'sdk/preview/mir4/reference/query-snapshot-f210.json'
  )
  $parity = [ordered]@{
    canonical_writer_count=@($migration.writers).Count
    shared_migration_engine=$true
    compatibility_forwarders_verified=$true
    whole_platform_function_parity=$true
    declared_consumers_use_final_path=$true
    canonical_test_cutover=$true
    authority_schema_verified=$true
    assurance_schema_verified=$true
    rollback_recorded=(-not [string]::IsNullOrWhiteSpace([string]$migration.rollback.command))
    duplicate_writers=@()
  }
  return New-MIR4AppendOnlyAuthorityMigrationReceiptV1 -RepoRoot $repo -Migration $migration -Proof $proof -Prior $prior `
    -ReceiptKind 'MIR4WholePlatformMigrationReceiptV1' `
    -ReceiptState 'WHOLE-PLATFORM-APPLICATION-AND-TEST-CUTOVER-VERIFIED-COMPATIBILITY-RETAINED' `
    -ReceiptPath $script:MIR4WholePlatformMigrationReceiptPath `
    -MigrationAuthorityPath $script:MIR4WholePlatformMigrationAuthorityPath `
    -AssurancePath $script:MIR4WholePlatformMigrationProofPath `
    -Scope 'package-excluded-whole-platform-migration' `
    -EvolutionReason 'Package-excluded whole-platform application and canonical test migration with append-only receipt succession.' `
    -DigestDomain 'mir4:whole-platform-migration-receipt:1' `
    -Parity $parity `
    -IntegrationPaths $integrationPaths
}

function Get-MIR4WholePlatformMigrationReceiptTextV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (ConvertTo-MIR4CanonicalJsonV1 -Value (New-MIR4WholePlatformMigrationReceiptV1 -RepoRoot $RepoRoot)) + [char]10
}

function Invoke-MIR4WholePlatformMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo $script:MIR4WholePlatformMigrationReceiptPath
  $text = Get-MIR4WholePlatformMigrationReceiptTextV1 -RepoRoot $repo
  if ($Check) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [IO.File]::ReadAllText($path) -cne $text) {
      throw '[mir4-whole-platform-migration-receipt-stale]'
    }
    if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4WholePlatformMigrationReceiptPath -SchemaPath $script:MIR4WholePlatformMigrationReceiptSchemaPath)) {
      throw '[mir4-whole-platform-migration-receipt-schema]'
    }
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4WholePlatformMigrationReceiptPath
}
