. (Join-Path $PSScriptRoot '../../domain/repository/RepositoryFixedPoint.ps1')
. (Join-Path $PSScriptRoot '../../adapters/repository/GitRepositoryInventory.ps1')
. (Join-Path $PSScriptRoot '../../../lib/mir4/CanonicalJsonV1.ps1')
. (Join-Path $PSScriptRoot '../../../lib/validation/PackageIdentity.ps1')
. (Join-Path $PSScriptRoot '../../../lib/mir4/PreFreezeRelease.ps1')

function Get-MIR4RepositoryFileSha256V1 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-MIR4RepositoryComponentHashModeV1 {
  param([Parameter(Mandatory)][string]$Path)
  return 'canonical-text-v1'
}

function Get-MIR4RepositoryComponentSha256V1 {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Mode)
  return Get-MIR4PreFreezeFileSha256 -Path $Path -Mode $Mode
}

function Invoke-MIR4RepositoryRootProjection {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authority = Get-MIR4RepositoryFixedPointAuthority -RepoRoot $repo
  foreach ($root in @($authority.visible_roots)) {
    $path = Join-Path $repo (([string]$root.path) + '/.mir-root.json')
    $json = (Get-MIR4RepositoryRootMarker -Root $root | ConvertTo-Json -Depth 20) + "`n"
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json.Replace("`r`n","`n"))
    if ($Check) {
      if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not [Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($path), [byte[]]$bytes)) {
        throw "[mir4-repository-root-projection-stale] $($root.path)"
      }
    } else {
      New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
      [IO.File]::WriteAllBytes($path, $bytes)
    }
  }
}

function Test-MIR4RepositoryCompatibilityForwardersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $contracts = @(
    [ordered]@{path='tools/lib/mir4/RepositoryFixedPoint.ps1';marker='MIR4-REPOSITORY-COMPATIBILITY-LIBRARY';target='mir/application/repository/RepositoryFixedPoint.ps1';max_lines=8},
    [ordered]@{path='tools/commands/mir4/Invoke-MIR4RepositoryFixedPoint.ps1';marker='MIR4-REPOSITORY-COMPATIBILITY-COMMAND';target='tools/mir/cli/Invoke-MIR4RepositoryFixedPoint.ps1';max_lines=16},
    [ordered]@{path='validation/tests/mir4/Test-MIR4RepositoryFixedPointW01.ps1';marker='MIR4-REPOSITORY-COMPATIBILITY-TEST';target='tests/repository/Test-MIR4RepositoryFixedPoint.ps1';max_lines=12}
  )
  foreach ($contract in $contracts) {
    $text = [IO.File]::ReadAllText((Join-Path $repo ([string]$contract.path)))
    if ($text -cnotmatch [regex]::Escape([string]$contract.marker) -or $text.Replace('\','/') -cnotmatch [regex]::Escape([string]$contract.target) -or $text.Split([char]10).Count -gt [int]$contract.max_lines) {
      throw "[mir4-repository-compatibility-forwarder] $($contract.path)"
    }
  }
  $cliText = [IO.File]::ReadAllText((Join-Path $repo 'tools/mir.ps1')).Replace('\','/')
  if ($cliText -cnotmatch [regex]::Escape('tools/mir/cli/Invoke-MIR4RepositoryFixedPoint.ps1')) { throw '[mir4-repository-cli-canonical-route]' }
  return $true
}

function New-MIR4RepositoryMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $migration = Get-MIR4RepositoryMigrationAuthorityV1 -RepoRoot $repo
  $proof = Get-MIR4RepositoryMigrationProofPolicyV1 -RepoRoot $repo
  $prior = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation
  [void](Get-MIR4RepositoryFixedPointAuthority -RepoRoot $repo)
  [void](Test-MIR4RepositoryCompatibilityForwardersV1 -RepoRoot $repo)

  $paths = @(
    '.gitattributes',
    $script:MIR4RepositoryFixedPointAuthorityPath,
    '.mir/assurance.json',
    '.mir/control/paths.yml',
    '.mir/control-plane/ownership.json',
    '.mir/modules.yml',
    '.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json',
    'validation/tests.yml',
    'tools/mir.ps1',
    $script:MIR4RepositoryMigrationAuthorityPath,
    $script:MIR4RepositoryMigrationAuthoritySchemaPath,
    $script:MIR4RepositoryMigrationProofPath,
    $script:MIR4RepositoryMigrationProofSchemaPath,
    $script:MIR4RepositoryMigrationReceiptSchemaPath
  ) + @($migration.path_map | Where-Object { [string]$_.final_path -cne $script:MIR4RepositoryMigrationReceiptPath } | ForEach-Object { [string]$_.final_path }) + @($migration.compatibility_entrypoints | ForEach-Object { [string]$_.path })
  $components = @(
    foreach ($path in @($paths | Sort-Object -Unique)) {
      $fullPath = Join-Path $repo $path
      if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "[mir4-repository-migration-component-missing] $path" }
      $mode = Get-MIR4RepositoryComponentHashModeV1 -Path $path
      [ordered]@{path=$path;sha256=(Get-MIR4RepositoryComponentSha256V1 -Path $fullPath -Mode $mode);hash_mode=$mode}
    }
  )
  $componentPaths = @($components | ForEach-Object { [string]$_.path })
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
        reason='Package-excluded repository fixed-point tooling and test authority migration.'
        scope='package-excluded-repository-migration'
        package_visible=$false
        release_authority=$false
      })
      [void]$currentPaths.Add($relativePath)
    }
  }
  foreach ($path in $componentPaths) { [void]$currentPaths.Add($path) }
  $componentByPath = @{}
  foreach ($component in $components) { $componentByPath[[string]$component.path] = $component }
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
    kind='MIR4RepositoryMigrationReceiptV1'
    migration_id=[string]$migration.migration_id
    state='TOOL-AND-TEST-WRITER-CUTOVER-VERIFIED-COMPATIBILITY-RETAINED'
    predecessor_receipt=[ordered]@{path=[string]$prior.prior_receipt_path;sha256=[string]$prior.prior_receipt_sha256}
    evolved_bindings=@($evolvedBindings)
    current_authorities=$currentAuthorities
    fixed_point_authority=[ordered]@{path=$script:MIR4RepositoryFixedPointAuthorityPath;sha256=(Get-MIR4RepositoryComponentSha256V1 -Path (Join-Path $repo $script:MIR4RepositoryFixedPointAuthorityPath) -Mode 'canonical-text-v1');hash_mode='canonical-text-v1'}
    migration_authority=[ordered]@{path=$script:MIR4RepositoryMigrationAuthorityPath;sha256=(Get-MIR4RepositoryComponentSha256V1 -Path (Join-Path $repo $script:MIR4RepositoryMigrationAuthorityPath) -Mode 'canonical-text-v1');hash_mode='canonical-text-v1'}
    assurance_policy=[ordered]@{path=$script:MIR4RepositoryMigrationProofPath;sha256=(Get-MIR4RepositoryComponentSha256V1 -Path (Join-Path $repo $script:MIR4RepositoryMigrationProofPath) -Mode 'canonical-text-v1');hash_mode='canonical-text-v1';required_test_id=[string]$proof.test_id}
    components=$components
    parity=[ordered]@{
      canonical_writer_count=@($migration.writers).Count
      compatibility_forwarders_verified=$true
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
  $receipt.digest = Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:repository-migration-receipt:1' -OmitTopLevelDigest
  return $receipt
}

function Get-MIR4RepositoryMigrationReceiptTextV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (ConvertTo-MIR4CanonicalJsonV1 -Value (New-MIR4RepositoryMigrationReceiptV1 -RepoRoot $RepoRoot)) + "`n"
}

function Invoke-MIR4RepositoryMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo $script:MIR4RepositoryMigrationReceiptPath
  $text = Get-MIR4RepositoryMigrationReceiptTextV1 -RepoRoot $repo
  if ($Check) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [IO.File]::ReadAllText($path) -cne $text) { throw '[mir4-repository-migration-receipt-stale]' }
    if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4RepositoryMigrationReceiptPath -SchemaPath $script:MIR4RepositoryMigrationReceiptSchemaPath)) { throw '[mir4-repository-migration-receipt-schema]' }
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4RepositoryMigrationReceiptPath
}
