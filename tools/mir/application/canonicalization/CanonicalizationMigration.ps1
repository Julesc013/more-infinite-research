. (Join-Path $PSScriptRoot '../../domain/repository/RepositoryFixedPoint.ps1')
. (Join-Path $PSScriptRoot '../../domain/canonicalization/CanonicalJsonV1.ps1')
. (Join-Path $PSScriptRoot '../../../lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $PSScriptRoot '../../../lib/validation/PackageIdentity.ps1')

$script:MIR4CanonicalizationMigrationAuthorityPath = 'governance/repository/migrations/canonicalization-tooling-v1.json'
$script:MIR4CanonicalizationMigrationAuthoritySchemaPath = 'contracts/repository/mir4-canonicalization-migration-authority-v1.schema.json'
$script:MIR4CanonicalizationMigrationProofPath = 'assurance/repository/canonicalization-tooling-v1.json'
$script:MIR4CanonicalizationMigrationProofSchemaPath = 'contracts/repository/mir4-canonicalization-migration-proof-v1.schema.json'
$script:MIR4CanonicalizationMigrationReceiptPath = 'releases/migrations/MIR4-Canonicalization-Tooling-MigrationV1.json'
$script:MIR4CanonicalizationMigrationReceiptSchemaPath = 'contracts/repository/mir4-canonicalization-migration-receipt-v1.schema.json'
$script:MIR4CanonicalizationPredecessorReceiptPath = 'releases/migrations/MIR4-Repository-Fixed-Point-Tooling-MigrationV1.json'
$script:MIR4CanonicalizationPredecessorReceiptSha256 = '5B188181285DB7F89E6F0CA91221F9028EEDF212CA62D5BEC2A56D59D3510D26'

function Get-MIR4CanonicalizationMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4CanonicalizationMigrationAuthorityPath -SchemaPath $script:MIR4CanonicalizationMigrationAuthoritySchemaPath)) {
    throw '[mir4-canonicalization-migration-authority-schema]'
  }
  $authority = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4CanonicalizationMigrationAuthorityPath
  if ([string]$authority.predecessor_receipt.path -cne $script:MIR4CanonicalizationPredecessorReceiptPath -or
      [string]$authority.predecessor_receipt.sha256 -cne $script:MIR4CanonicalizationPredecessorReceiptSha256) {
    throw '[mir4-canonicalization-migration-predecessor-authority]'
  }
  if (@($authority.writers).Count -ne 1 -or [string]$authority.writers[0].path -cne 'tools/mir/application/canonicalization/CanonicalizationMigration.ps1') {
    throw '[mir4-canonicalization-migration-single-writer]'
  }
  $finalPaths = @($authority.path_map | ForEach-Object { [string]$_.final_path })
  if (@($finalPaths | Sort-Object -Unique).Count -ne $finalPaths.Count) { throw '[mir4-canonicalization-migration-duplicate-final-path]' }
  if (@($authority.release_transition_authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
    throw '[mir4-canonicalization-migration-release-authority]'
  }
  return $authority
}

function Get-MIR4CanonicalizationMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4CanonicalizationMigrationProofPath -SchemaPath $script:MIR4CanonicalizationMigrationProofSchemaPath)) {
    throw '[mir4-canonicalization-migration-proof-schema]'
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4CanonicalizationMigrationProofPath
}

function Test-MIR4CanonicalizationCompatibilityForwardersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $contracts = @(
    [ordered]@{path='tools/lib/mir4/CanonicalJsonV1.ps1';marker='MIR4-CANONICALIZATION-COMPATIBILITY-LIBRARY';target='mir/domain/canonicalization/CanonicalJsonV1.ps1';max_lines=5},
    [ordered]@{path='validation/tests/mir4/Test-MIR4CanonicalizationDiagnosticsT07.ps1';marker='MIR4-CANONICALIZATION-COMPATIBILITY-TEST';target='tests/canonicalization/Test-MIR4CanonicalizationDiagnostics.ps1';max_lines=6}
  )
  foreach ($contract in $contracts) {
    $text = [IO.File]::ReadAllText((Join-Path $repo ([string]$contract.path)))
    if ($text -cnotmatch [regex]::Escape([string]$contract.marker) -or
        $text.Replace('\','/') -cnotmatch [regex]::Escape([string]$contract.target) -or
        $text.Split([char]10).Count -gt [int]$contract.max_lines) {
      throw "[mir4-canonicalization-compatibility-forwarder] $($contract.path)"
    }
  }
  return $true
}

function Get-MIR4CanonicalizationMigrationComponentSha256V1 {
  param([Parameter(Mandatory)][string]$Path)
  return Get-MIR4PreFreezeFileSha256 -Path $Path -Mode 'canonical-text-v1'
}

function New-MIR4CanonicalizationMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $migration = Get-MIR4CanonicalizationMigrationAuthorityV1 -RepoRoot $repo
  $proof = Get-MIR4CanonicalizationMigrationProofPolicyV1 -RepoRoot $repo
  $prior = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration
  if ([string]$prior.prior_receipt_path -cne $script:MIR4CanonicalizationPredecessorReceiptPath -or
      [string]$prior.prior_receipt_sha256 -cne $script:MIR4CanonicalizationPredecessorReceiptSha256) {
    throw '[mir4-canonicalization-migration-predecessor-chain]'
  }
  $predecessorPath = Join-Path $repo $script:MIR4CanonicalizationPredecessorReceiptPath
  if ((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash -cne $script:MIR4CanonicalizationPredecessorReceiptSha256) {
    throw '[mir4-canonicalization-migration-predecessor-bytes]'
  }
  [void](Test-MIR4CanonicalizationCompatibilityForwardersV1 -RepoRoot $repo)

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
    'tools/lib/mir4/ExperimentalApiSdk.ps1',
    'tools/lib/mir4/EnvironmentEvidence.ps1',
    'tools/lib/mir4/ModuleEcosystem.ps1',
    'tools/lib/mir4/WholePlatform.ps1',
    'tools/commands/mir4/Invoke-MIR4WholePlatform.ps1',
    'tools/mir/application/repository/RepositoryFixedPoint.ps1',
    'tools/mir/cli/Invoke-MIR4RepositoryFixedPoint.ps1',
    'tests/repository/Test-MIR4RepositoryFixedPoint.ps1',
    'docs/architecture/mir4-repository-fixed-point.md',
    'docs/architecture/module-boundaries.md',
    'docs/reference/generated/mir4-whole-platform-matrix.md',
    'mir.lock',
    'sdk/preview/mir4/canonical-json-v1/powershell/MIR4.CanonicalJson.V1.psm1',
    'sdk/preview/mir4/reference/compilation-runs.json',
    'sdk/preview/mir4/reference/inspection-bundle-v1.json',
    'sdk/preview/mir4/reference/inspector-workbench-result-v1.json',
    'sdk/preview/mir4/reference/query-snapshot-f210.json'
  )
  $paths = @($integrationPaths) +
    @($migration.path_map | Where-Object { [string]$_.final_path -cne $script:MIR4CanonicalizationMigrationReceiptPath } | ForEach-Object { [string]$_.final_path }) +
    @($migration.compatibility_entrypoints | ForEach-Object { [string]$_.path })
  $components = @(
    foreach ($path in @($paths | Sort-Object -Unique)) {
      $fullPath = Join-Path $repo $path
      if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "[mir4-canonicalization-migration-component-missing] $path" }
      [ordered]@{path=$path;sha256=(Get-MIR4CanonicalizationMigrationComponentSha256V1 -Path $fullPath);hash_mode='canonical-text-v1'}
    }
  )
  $componentPaths = @($components | ForEach-Object { [string]$_.path })
  $componentByPath = @{}
  foreach ($component in $components) { $componentByPath[[string]$component.path] = $component }
  $evolvedBindings = [Collections.Generic.List[object]]::new()
  $currentPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($entry in @($prior.authority_hashes.GetEnumerator() | Sort-Object Key)) {
    $relativePath = [string]$entry.Key
    $fullPath = Join-Path $repo $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
    $mode = if ($prior.authority_hash_modes.ContainsKey($relativePath)) { [string]$prior.authority_hash_modes[$relativePath] } else { 'raw-bytes' }
    $actual = Get-MIR4PreFreezeFileSha256 -Path $fullPath -Mode $mode
    if ($actual -cne [string]$entry.Value) {
      $evolvedBindings.Add([ordered]@{
        path=$relativePath
        previous_sha256=[string]$entry.Value
        current_sha256=$actual
        hash_mode=$mode
        reason='Package-excluded canonicalization implementation and test authority migration with append-only receipt succession.'
        scope='package-excluded-canonicalization-migration'
        package_visible=$false
        release_authority=$false
      })
      [void]$currentPaths.Add($relativePath)
    }
  }
  foreach ($path in $componentPaths) { [void]$currentPaths.Add($path) }
  $currentAuthorities = @(
    foreach ($relativePath in @($currentPaths | Sort-Object)) {
      $mode = if ($prior.authority_hash_modes.ContainsKey($relativePath)) { [string]$prior.authority_hash_modes[$relativePath] }
        elseif ($componentByPath.ContainsKey($relativePath)) { [string]$componentByPath[$relativePath].hash_mode }
        else { 'raw-bytes' }
      $role = if ($relativePath -in $componentPaths -and $prior.authority_hashes.ContainsKey($relativePath)) { 'migration-component-and-evolved-authority' }
        elseif ($relativePath -in $componentPaths) { 'migration-component' }
        else { 'evolved-authority' }
      [ordered]@{path=$relativePath;sha256=(Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo $relativePath) -Mode $mode);hash_mode=$mode;role=$role}
    }
  )
  $receipt = [ordered]@{
    schema=1
    kind='MIR4CanonicalizationMigrationReceiptV1'
    migration_id=[string]$migration.migration_id
    state='CANONICALIZATION-TOOL-AND-TEST-WRITER-CUTOVER-VERIFIED-COMPATIBILITY-RETAINED'
    predecessor_receipt=[ordered]@{path=[string]$prior.prior_receipt_path;sha256=[string]$prior.prior_receipt_sha256}
    predecessor_immutability=[ordered]@{path=$script:MIR4CanonicalizationPredecessorReceiptPath;sha256=$script:MIR4CanonicalizationPredecessorReceiptSha256;byte_length=(Get-Item -LiteralPath $predecessorPath).Length;raw_bytes_verified=$true}
    evolved_bindings=@($evolvedBindings)
    current_authorities=$currentAuthorities
    fixed_point_authority=[ordered]@{path='.mir/control/repository-fixed-point.json';sha256=(Get-MIR4CanonicalizationMigrationComponentSha256V1 -Path (Join-Path $repo '.mir/control/repository-fixed-point.json'));hash_mode='canonical-text-v1'}
    migration_authority=[ordered]@{path=$script:MIR4CanonicalizationMigrationAuthorityPath;sha256=(Get-MIR4CanonicalizationMigrationComponentSha256V1 -Path (Join-Path $repo $script:MIR4CanonicalizationMigrationAuthorityPath));hash_mode='canonical-text-v1'}
    assurance_policy=[ordered]@{path=$script:MIR4CanonicalizationMigrationProofPath;sha256=(Get-MIR4CanonicalizationMigrationComponentSha256V1 -Path (Join-Path $repo $script:MIR4CanonicalizationMigrationProofPath));hash_mode='canonical-text-v1';required_test_id=[string]$proof.test_id}
    components=$components
    parity=[ordered]@{
      canonical_writer_count=@($migration.writers).Count
      compatibility_forwarders_verified=$true
      functional_test_path_cutover=$true
      authority_schema_verified=$true
      assurance_schema_verified=$true
      rollback_recorded=(-not [string]::IsNullOrWhiteSpace([string]$migration.rollback.command))
      duplicate_writers=@()
    }
    activated_roots=@($migration.activated_roots)
    package_source_sha256=Get-MIRPackageSourceFingerprint -RepoRoot $repo
    package_visible_delta=@()
    sunset=[ordered]@{state=[string]$migration.sunset.state;compatibility_paths=@($migration.compatibility_entrypoints | ForEach-Object { [string]$_.path });required_gates=@($migration.sunset.required_gates)}
    transition_gate=[ordered]@{source_freeze=$false;candidate_allocation=$false;production_signing=$false;seal=$false;promotion=$false;tagging=$false;publication=$false}
    release_transition_authority=[ordered]@{source_freeze=$false;candidate_allocation=$false;production_signing=$false;seal=$false;promotion=$false;tagging=$false;publication=$false}
    digest=$null
  }
  $receipt.digest = Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:canonicalization-migration-receipt:1' -OmitTopLevelDigest
  return $receipt
}

function Get-MIR4CanonicalizationMigrationReceiptTextV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (ConvertTo-MIR4CanonicalJsonV1 -Value (New-MIR4CanonicalizationMigrationReceiptV1 -RepoRoot $RepoRoot)) + "`n"
}

function Invoke-MIR4CanonicalizationMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo $script:MIR4CanonicalizationMigrationReceiptPath
  $text = Get-MIR4CanonicalizationMigrationReceiptTextV1 -RepoRoot $repo
  if ($Check) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [IO.File]::ReadAllText($path) -cne $text) {
      throw '[mir4-canonicalization-migration-receipt-stale]'
    }
    if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4CanonicalizationMigrationReceiptPath -SchemaPath $script:MIR4CanonicalizationMigrationReceiptSchemaPath)) {
      throw '[mir4-canonicalization-migration-receipt-schema]'
    }
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4CanonicalizationMigrationReceiptPath
}
