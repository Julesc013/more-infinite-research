. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot '../../domain/diagnostics/DiagnosticsV1.ps1')

$script:MIR4DiagnosticsMigrationAuthorityPath = 'governance/repository/migrations/diagnostics-tooling-v1.json'
$script:MIR4DiagnosticsMigrationAuthoritySchemaPath = 'contracts/repository/mir4-diagnostics-migration-authority-v1.schema.json'
$script:MIR4DiagnosticsMigrationProofPath = 'assurance/repository/diagnostics-tooling-v1.json'
$script:MIR4DiagnosticsMigrationProofSchemaPath = 'contracts/repository/mir4-diagnostics-migration-proof-v1.schema.json'
$script:MIR4DiagnosticsMigrationReceiptPath = 'releases/migrations/MIR4-Diagnostics-Tooling-MigrationV1.json'
$script:MIR4DiagnosticsMigrationReceiptSchemaPath = 'contracts/repository/mir4-diagnostics-migration-receipt-v1.schema.json'
$script:MIR4DiagnosticsPredecessorReceiptPath = 'releases/migrations/MIR4-Canonicalization-Tooling-MigrationV1.json'
$script:MIR4DiagnosticsPredecessorReceiptSha256 = 'B126E835EDE63832D62833B4A96FD888301DB608858A1D94BC2D4B93F7ADA27A'
$script:MIR4DiagnosticsRegistrySha256 = '76DEC33A6807AFB32D9B9D197FF22A65AEC2613F9B7F04CE576D49D8C44238EB'
$script:MIR4DiagnosticsParityDigestV1 = 'sha256:d4b385e5173f167e274fd7f55ddd3debbf658ee860a0e438db8da3ebe6f7c50e'

function Get-MIR4DiagnosticsMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4DiagnosticsMigrationAuthorityPath -SchemaPath $script:MIR4DiagnosticsMigrationAuthoritySchemaPath)) {
    throw '[mir4-diagnostics-migration-authority-schema]'
  }
  $authority = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4DiagnosticsMigrationAuthorityPath
  if ([string]$authority.predecessor_receipt.path -cne $script:MIR4DiagnosticsPredecessorReceiptPath -or
      [string]$authority.predecessor_receipt.sha256 -cne $script:MIR4DiagnosticsPredecessorReceiptSha256) {
    throw '[mir4-diagnostics-migration-predecessor-authority]'
  }
  if (@($authority.writers).Count -ne 1 -or [string]$authority.writers[0].path -cne 'tools/mir/application/diagnostics/DiagnosticsMigration.ps1') {
    throw '[mir4-diagnostics-migration-single-writer]'
  }
  $finalPaths = @($authority.path_map | ForEach-Object { [string]$_.final_path })
  if (@($finalPaths | Sort-Object -Unique).Count -ne $finalPaths.Count) { throw '[mir4-diagnostics-migration-duplicate-final-path]' }
  if (@($authority.release_transition_authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
    throw '[mir4-diagnostics-migration-release-authority]'
  }
  return $authority
}

function Get-MIR4DiagnosticsMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4DiagnosticsMigrationProofPath -SchemaPath $script:MIR4DiagnosticsMigrationProofSchemaPath)) {
    throw '[mir4-diagnostics-migration-proof-schema]'
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4DiagnosticsMigrationProofPath
}

function Test-MIR4DiagnosticsCompatibilityForwarderV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = 'tools/lib/mir4/DiagnosticsV1.ps1'
  $text = [IO.File]::ReadAllText((Join-Path $repo $path)).Replace('\','/')
  if ($text -cnotmatch 'MIR4-DIAGNOSTICS-COMPATIBILITY-LIBRARY' -or
      $text -cnotmatch [regex]::Escape('mir/domain/diagnostics/DiagnosticsV1.ps1') -or
      $text.Split([char]10).Count -gt 4) {
    throw "[mir4-diagnostics-compatibility-forwarder] $path"
  }
  return $true
}

function Test-MIR4DiagnosticsDeclaredConsumersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  foreach ($path in @('tools/lib/mir4/ModuleEcosystem.ps1','tests/canonicalization/Test-MIR4CanonicalizationDiagnostics.ps1','tools/lib/mir4/PlatformPreview.ps1')) {
    $text = [IO.File]::ReadAllText((Join-Path $repo $path)).Replace('\','/')
    if ($text -cnotmatch [regex]::Escape('tools/mir/domain/diagnostics/DiagnosticsV1.ps1') -and
        $text -cnotmatch [regex]::Escape('mir/domain/diagnostics/DiagnosticsV1.ps1')) {
      throw "[mir4-diagnostics-consumer-final-path] $path"
    }
  }
  return $true
}

function Get-MIR4DiagnosticsFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $registryPath = Join-Path $repo 'spec/api/mir4-v1/diagnostics.json'
  $registry = Get-MIR4DiagnosticRegistryV1 -RepoRoot $repo
  $diagnostics = @(
    New-MIR4DiagnosticV1 -RepoRoot $repo -Code 'MIR4-MEP-016' -Path '$.host' -Context ([ordered]@{present=$false})
    New-MIR4DiagnosticV1 -RepoRoot $repo -Code 'MIR4-CANON-002' -Path '$.number' -Context ([ordered]@{value='1.0'})
    New-MIR4DiagnosticV1 -RepoRoot $repo -Code 'MIR4-API-001' -Path '$.availability' -Context ([ordered]@{value='unknown'})
  )
  $sorted = @(Sort-MIR4DiagnosticsV1 -Diagnostics $diagnostics)
  $record = [ordered]@{
    registry_sha256=(Get-MIR4PreFreezeFileSha256 -Path $registryPath -Mode 'canonical-text-v1')
    registry_count=@($registry.diagnostics).Count
    registry_codes=@($registry.diagnostics | ForEach-Object { [string]$_.code })
    samples=@($sorted | ForEach-Object { [ordered]@{code=[string]$_.code;severity=[string]$_.severity;order=[int]$_.order;path=[string]$_.path;message=[string]$_.message;context=$_.context} })
    rendered=@($sorted | ForEach-Object { Format-MIR4DiagnosticV1 $_ })
  }
  return [pscustomobject][ordered]@{
    record=$record
    digest=(Get-MIR4CanonicalDigestV1 -Value $record -Domain 'mir4:diagnostics-functional-parity:1')
  }
}

function Test-MIR4DiagnosticsFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $result = Get-MIR4DiagnosticsFunctionalParityV1 -RepoRoot $RepoRoot
  if ([string]$result.record.registry_sha256 -cne $script:MIR4DiagnosticsRegistrySha256) { throw '[mir4-diagnostics-registry-byte-parity]' }
  if ([int]$result.record.registry_count -ne 43 -or [string]$result.record.registry_codes[0] -cne 'MIR4-API-001' -or [string]$result.record.registry_codes[-1] -cne 'MIR4-MEP-016') {
    throw '[mir4-diagnostics-registry-shape-parity]'
  }
  if ([string]$result.digest -cne $script:MIR4DiagnosticsParityDigestV1) { throw '[mir4-diagnostics-functional-parity]' }
  return $result
}

function New-MIR4DiagnosticsMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $migration = Get-MIR4DiagnosticsMigrationAuthorityV1 -RepoRoot $repo
  $proof = Get-MIR4DiagnosticsMigrationProofPolicyV1 -RepoRoot $repo
  $prior = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration
  [void](Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo -ReceiptPath $script:MIR4DiagnosticsPredecessorReceiptPath -ExpectedSha256 $script:MIR4DiagnosticsPredecessorReceiptSha256 -SchemaPath 'contracts/repository/mir4-canonicalization-migration-receipt-v1.schema.json' -Kind 'MIR4CanonicalizationMigrationReceiptV1' -DigestDomain 'mir4:canonicalization-migration-receipt:1' -ErrorPrefix 'mir4-diagnostics-predecessor')
  [void](Test-MIR4DiagnosticsCompatibilityForwarderV1 -RepoRoot $repo)
  [void](Test-MIR4DiagnosticsDeclaredConsumersV1 -RepoRoot $repo)
  [void](Test-MIR4DiagnosticsFunctionalParityV1 -RepoRoot $repo)

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
    'tools/lib/mir4/ModuleEcosystem.ps1',
    'tools/mir/domain/repository/RepositoryFixedPoint.ps1',
    'tools/mir/application/canonicalization/CanonicalizationMigration.ps1',
    'tools/mir/cli/Invoke-MIR4CanonicalizationMigration.ps1',
    'tests/canonicalization/Test-MIR4CanonicalizationMigration.ps1',
    'tests/canonicalization/Test-MIR4CanonicalizationDiagnostics.ps1',
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
    diagnostics_registry_parity=$true
    diagnostic_function_parity=$true
    declared_consumers_use_final_path=$true
    focused_test_registered=$true
    authority_schema_verified=$true
    assurance_schema_verified=$true
    rollback_recorded=(-not [string]::IsNullOrWhiteSpace([string]$migration.rollback.command))
    duplicate_writers=@()
  }
  return New-MIR4AppendOnlyAuthorityMigrationReceiptV1 -RepoRoot $repo -Migration $migration -Proof $proof -Prior $prior `
    -ReceiptKind 'MIR4DiagnosticsMigrationReceiptV1' `
    -ReceiptState 'DIAGNOSTICS-DOMAIN-AND-TEST-CUTOVER-VERIFIED-COMPATIBILITY-RETAINED' `
    -ReceiptPath $script:MIR4DiagnosticsMigrationReceiptPath `
    -MigrationAuthorityPath $script:MIR4DiagnosticsMigrationAuthorityPath `
    -AssurancePath $script:MIR4DiagnosticsMigrationProofPath `
    -Scope 'package-excluded-diagnostics-migration' `
    -EvolutionReason 'Package-excluded diagnostics implementation and focused test migration with reusable append-only receipt succession.' `
    -DigestDomain 'mir4:diagnostics-migration-receipt:1' `
    -Parity $parity `
    -IntegrationPaths $integrationPaths
}

function Get-MIR4DiagnosticsMigrationReceiptTextV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (ConvertTo-MIR4CanonicalJsonV1 -Value (New-MIR4DiagnosticsMigrationReceiptV1 -RepoRoot $RepoRoot)) + [char]10
}

function Invoke-MIR4DiagnosticsMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo $script:MIR4DiagnosticsMigrationReceiptPath
  $text = Get-MIR4DiagnosticsMigrationReceiptTextV1 -RepoRoot $repo
  if ($Check) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [IO.File]::ReadAllText($path) -cne $text) {
      throw '[mir4-diagnostics-migration-receipt-stale]'
    }
    if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4DiagnosticsMigrationReceiptPath -SchemaPath $script:MIR4DiagnosticsMigrationReceiptSchemaPath)) {
      throw '[mir4-diagnostics-migration-receipt-schema]'
    }
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4DiagnosticsMigrationReceiptPath
}
