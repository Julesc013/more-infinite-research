. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot '../../domain/targets/TargetKey.ps1')

$script:MIR4TargetKeyMigrationAuthorityPath = 'governance/repository/migrations/target-key-tooling-v1.json'
$script:MIR4TargetKeyMigrationAuthoritySchemaPath = 'contracts/repository/mir4-target-key-migration-authority-v1.schema.json'
$script:MIR4TargetKeyMigrationProofPath = 'assurance/repository/target-key-tooling-v1.json'
$script:MIR4TargetKeyMigrationProofSchemaPath = 'contracts/repository/mir4-target-key-migration-proof-v1.schema.json'
$script:MIR4TargetKeyMigrationReceiptPath = 'releases/migrations/MIR4-Target-Key-Tooling-MigrationV1.json'
$script:MIR4TargetKeyMigrationReceiptSchemaPath = 'contracts/repository/mir4-target-key-migration-receipt-v1.schema.json'
$script:MIR4TargetKeyPredecessorReceiptPath = 'releases/migrations/MIR4-Diagnostics-Tooling-MigrationV1.json'
$script:MIR4TargetKeyPredecessorReceiptSha256 = 'EB7CB542741401A93F53261A4B90A9D17D128C8C97E2D68626088D181743F4A6'
$script:MIR4TargetKeyParityDigestV1 = 'sha256:b6bb128bf5f1d312ec3cbe5f8ead03a9ad56b5a1b664514a196960ecc29c7f8e'

function Get-MIR4TargetKeyMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4TargetKeyMigrationAuthorityPath -SchemaPath $script:MIR4TargetKeyMigrationAuthoritySchemaPath)) {
    throw '[mir4-target-key-migration-authority-schema]'
  }
  $authority = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4TargetKeyMigrationAuthorityPath
  if ([string]$authority.predecessor_receipt.path -cne $script:MIR4TargetKeyPredecessorReceiptPath -or
      [string]$authority.predecessor_receipt.sha256 -cne $script:MIR4TargetKeyPredecessorReceiptSha256) {
    throw '[mir4-target-key-migration-predecessor-authority]'
  }
  if (@($authority.writers).Count -ne 1 -or [string]$authority.writers[0].path -cne 'tools/mir/application/targets/TargetKeyMigration.ps1') {
    throw '[mir4-target-key-migration-single-writer]'
  }
  $finalPaths = @($authority.path_map | ForEach-Object { [string]$_.final_path })
  if (@($finalPaths | Sort-Object -Unique).Count -ne $finalPaths.Count) { throw '[mir4-target-key-migration-duplicate-final-path]' }
  if (@($authority.release_transition_authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
    throw '[mir4-target-key-migration-release-authority]'
  }
  return $authority
}

function Get-MIR4TargetKeyMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4TargetKeyMigrationProofPath -SchemaPath $script:MIR4TargetKeyMigrationProofSchemaPath)) {
    throw '[mir4-target-key-migration-proof-schema]'
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4TargetKeyMigrationProofPath
}

function Test-MIR4TargetKeyCompatibilityForwarderV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = 'tools/lib/mir4/TargetKey.ps1'
  $text = [IO.File]::ReadAllText((Join-Path $repo $path)).Replace('\','/')
  if ($text -cnotmatch 'MIR4-TARGET-KEY-COMPATIBILITY-LIBRARY' -or
      $text -cnotmatch [regex]::Escape('mir/domain/targets/TargetKey.ps1') -or
      $text.Split([char]10).Count -gt 4) {
    throw "[mir4-target-key-compatibility-forwarder] $path"
  }
  return $true
}

function Test-MIR4TargetKeyDeclaredConsumersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  foreach ($path in @('tools/mir.ps1','tools/lib/mir4/WholePlatform.ps1','tools/lib/mir4/TechnologyAcceptance.ps1','tools/lib/mir4/PlatformPreview.ps1')) {
    $text = [IO.File]::ReadAllText((Join-Path $repo $path)).Replace('\','/')
    if ($text -cnotmatch [regex]::Escape('mir/domain/targets/TargetKey.ps1')) {
      throw "[mir4-target-key-consumer-final-path] $path"
    }
  }
  return $true
}

function Get-MIR4TargetKeyFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $cases = @(
    foreach ($inputValue in @('F210','f210','F200','f200','F019','f019')) {
      $projection = New-MIR4TargetKeyProjection -Target $inputValue
      [ordered]@{
        input=$inputValue
        target=[string]$projection.target
        legacy_target=[string]$projection.legacy_target
        distribution_target_code=[string]$projection.distribution_target_code
      }
    }
  )
  $invalid = @(
    foreach ($inputValue in @('','210','F21','F2100','x210','Ｆ210')) {
      $message = $null
      try { ConvertTo-MIR4TargetKey -Target $inputValue | Out-Null } catch { $message = $_.Exception.Message }
      [ordered]@{input=$inputValue;message=$message}
    }
  )
  $record = [ordered]@{
    patterns=[ordered]@{display=$script:MIR4TargetDisplayPattern;legacy=$script:MIR4LegacyTargetPattern}
    cases=$cases
    invalid=$invalid
  }
  return [pscustomobject][ordered]@{
    record=$record
    digest=(Get-MIR4CanonicalDigestV1 -Value $record -Domain 'mir4:target-key-functional-parity:1')
  }
}

function Test-MIR4TargetKeyFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $result = Get-MIR4TargetKeyFunctionalParityV1 -RepoRoot $RepoRoot
  if (@($result.record.cases).Count -ne 6 -or @($result.record.invalid).Count -ne 6) { throw '[mir4-target-key-functional-shape-parity]' }
  if ([string]$result.record.cases[0].target -cne 'F210' -or [string]$result.record.cases[-1].distribution_target_code -cne '019') {
    throw '[mir4-target-key-projection-parity]'
  }
  if ([string]$result.digest -cne $script:MIR4TargetKeyParityDigestV1) { throw '[mir4-target-key-functional-parity]' }
  return $result
}

function New-MIR4TargetKeyMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $migration = Get-MIR4TargetKeyMigrationAuthorityV1 -RepoRoot $repo
  $proof = Get-MIR4TargetKeyMigrationProofPolicyV1 -RepoRoot $repo
  $prior = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration
  [void](Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo -ReceiptPath $script:MIR4TargetKeyPredecessorReceiptPath -ExpectedSha256 $script:MIR4TargetKeyPredecessorReceiptSha256 -SchemaPath 'contracts/repository/mir4-diagnostics-migration-receipt-v1.schema.json' -Kind 'MIR4DiagnosticsMigrationReceiptV1' -DigestDomain 'mir4:diagnostics-migration-receipt:1' -ErrorPrefix 'mir4-target-key-predecessor')
  [void](Test-MIR4TargetKeyCompatibilityForwarderV1 -RepoRoot $repo)
  [void](Test-MIR4TargetKeyDeclaredConsumersV1 -RepoRoot $repo)
  [void](Test-MIR4TargetKeyFunctionalParityV1 -RepoRoot $repo)

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
    'tools/lib/mir4/WholePlatform.ps1',
    'tools/lib/mir4/TechnologyAcceptance.ps1',
    'tools/mir/domain/repository/RepositoryFixedPoint.ps1',
    'tools/mir/application/diagnostics/DiagnosticsMigration.ps1',
    'tools/mir/cli/Invoke-MIR4DiagnosticsMigration.ps1',
    'tests/diagnostics/Test-MIR4DiagnosticsMigration.ps1',
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
    compatibility_forwarder_verified=$true
    target_key_function_parity=$true
    declared_consumers_use_final_path=$true
    focused_test_registered=$true
    authority_schema_verified=$true
    assurance_schema_verified=$true
    rollback_recorded=(-not [string]::IsNullOrWhiteSpace([string]$migration.rollback.command))
    duplicate_writers=@()
  }
  return New-MIR4AppendOnlyAuthorityMigrationReceiptV1 -RepoRoot $repo -Migration $migration -Proof $proof -Prior $prior `
    -ReceiptKind 'MIR4TargetKeyMigrationReceiptV1' `
    -ReceiptState 'TARGET-KEY-DOMAIN-AND-TEST-CUTOVER-VERIFIED-COMPATIBILITY-RETAINED' `
    -ReceiptPath $script:MIR4TargetKeyMigrationReceiptPath `
    -MigrationAuthorityPath $script:MIR4TargetKeyMigrationAuthorityPath `
    -AssurancePath $script:MIR4TargetKeyMigrationProofPath `
    -Scope 'package-excluded-target-key-migration' `
    -EvolutionReason 'Package-excluded target-key implementation and focused test migration with append-only receipt succession.' `
    -DigestDomain 'mir4:target-key-migration-receipt:1' `
    -Parity $parity `
    -IntegrationPaths $integrationPaths
}

function Get-MIR4TargetKeyMigrationReceiptTextV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (ConvertTo-MIR4CanonicalJsonV1 -Value (New-MIR4TargetKeyMigrationReceiptV1 -RepoRoot $RepoRoot)) + [char]10
}

function Invoke-MIR4TargetKeyMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo $script:MIR4TargetKeyMigrationReceiptPath
  $text = Get-MIR4TargetKeyMigrationReceiptTextV1 -RepoRoot $repo
  if ($Check) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [IO.File]::ReadAllText($path) -cne $text) {
      throw '[mir4-target-key-migration-receipt-stale]'
    }
    if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4TargetKeyMigrationReceiptPath -SchemaPath $script:MIR4TargetKeyMigrationReceiptSchemaPath)) {
      throw '[mir4-target-key-migration-receipt-schema]'
    }
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4TargetKeyMigrationReceiptPath
}
