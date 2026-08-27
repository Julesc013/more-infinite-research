. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot '../../domain/targets/TargetKey.ps1')

$script:MIR4TargetKeyMigrationAuthorityPath = 'governance/repository/migrations/target-key-tooling-v1.json'
$script:MIR4TargetKeyMigrationAuthoritySchemaPath = 'contracts/repository/mir4-target-key-migration-authority-v1.schema.json'
$script:MIR4TargetKeyMigrationProofPath = 'assurance/repository/target-key-tooling-v1.json'
$script:MIR4TargetKeyMigrationProofSchemaPath = 'contracts/repository/mir4-target-key-migration-proof-v1.schema.json'
$script:MIR4TargetKeyMigrationReceiptPath = 'releases/migrations/MIR4-Target-Key-Tooling-MigrationV1.json'
$script:MIR4TargetKeyMigrationReceiptSchemaPath = 'contracts/repository/mir4-target-key-migration-receipt-v1.schema.json'
$script:MIR4TargetKeyMigrationReceiptSha256 = '79E3ECC14FDC354A3F2509F4AC3366E790547F6E606B2F65096E7CFD5866C06D'
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
  $bindings = [ordered]@{
    'tools/mir.ps1' = 'mir/domain/targets/TargetKey.ps1'
    'tools/mir/application/platform/WholePlatform.ps1' = 'domain/targets/TargetKey.ps1'
    'tools/lib/mir4/TechnologyAcceptance.ps1' = 'mir/domain/targets/TargetKey.ps1'
    'tools/lib/mir4/PlatformPreview.ps1' = 'mir/domain/targets/TargetKey.ps1'
  }
  foreach ($entry in $bindings.GetEnumerator()) {
    $text = [IO.File]::ReadAllText((Join-Path $repo ([string]$entry.Key))).Replace('\','/')
    if ($text -cnotmatch [regex]::Escape([string]$entry.Value)) {
      throw "[mir4-target-key-consumer-final-path] $($entry.Key)"
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
  throw '[mir4-target-key-migration-receipt-immutable]'
}

function Get-MIR4TargetKeyMigrationReceiptTextV1 {
  throw '[mir4-target-key-migration-receipt-immutable]'
}

function Test-MIR4TargetKeyHistoricalMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $RepoRoot `
    -ReceiptPath $script:MIR4TargetKeyMigrationReceiptPath `
    -ExpectedSha256 $script:MIR4TargetKeyMigrationReceiptSha256 `
    -SchemaPath $script:MIR4TargetKeyMigrationReceiptSchemaPath `
    -Kind 'MIR4TargetKeyMigrationReceiptV1' `
    -DigestDomain 'mir4:target-key-migration-receipt:1' `
    -ErrorPrefix 'mir4-target-key-migration'
}

function Invoke-MIR4TargetKeyMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  if (-not $Check) { throw '[mir4-target-key-migration-receipt-immutable]' }
  return Test-MIR4TargetKeyHistoricalMigrationReceiptV1 -RepoRoot $RepoRoot
}
