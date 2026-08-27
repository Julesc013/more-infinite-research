. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot '../../domain/diagnostics/DiagnosticsV1.ps1')

$script:MIR4DiagnosticsMigrationAuthorityPath = 'governance/repository/migrations/diagnostics-tooling-v1.json'
$script:MIR4DiagnosticsMigrationAuthoritySchemaPath = 'contracts/repository/mir4-diagnostics-migration-authority-v1.schema.json'
$script:MIR4DiagnosticsMigrationProofPath = 'assurance/repository/diagnostics-tooling-v1.json'
$script:MIR4DiagnosticsMigrationProofSchemaPath = 'contracts/repository/mir4-diagnostics-migration-proof-v1.schema.json'
$script:MIR4DiagnosticsMigrationReceiptPath = 'releases/migrations/MIR4-Diagnostics-Tooling-MigrationV1.json'
$script:MIR4DiagnosticsMigrationReceiptSchemaPath = 'contracts/repository/mir4-diagnostics-migration-receipt-v1.schema.json'
$script:MIR4DiagnosticsMigrationReceiptSha256 = 'EB7CB542741401A93F53261A4B90A9D17D128C8C97E2D68626088D181743F4A6'
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
  throw '[mir4-diagnostics-migration-receipt-immutable]'
}

function Get-MIR4DiagnosticsMigrationReceiptTextV1 {
  throw '[mir4-diagnostics-migration-receipt-immutable]'
}

function Test-MIR4DiagnosticsHistoricalMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $RepoRoot `
    -ReceiptPath $script:MIR4DiagnosticsMigrationReceiptPath `
    -ExpectedSha256 $script:MIR4DiagnosticsMigrationReceiptSha256 `
    -SchemaPath $script:MIR4DiagnosticsMigrationReceiptSchemaPath `
    -Kind 'MIR4DiagnosticsMigrationReceiptV1' `
    -DigestDomain 'mir4:diagnostics-migration-receipt:1' `
    -ErrorPrefix 'mir4-diagnostics-migration'
}

function Invoke-MIR4DiagnosticsMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  if (-not $Check) { throw '[mir4-diagnostics-migration-receipt-immutable]' }
  return Test-MIR4DiagnosticsHistoricalMigrationReceiptV1 -RepoRoot $RepoRoot
}
