. (Join-Path $PSScriptRoot '../../domain/repository/RepositoryFixedPoint.ps1')
. (Join-Path $PSScriptRoot '../../domain/canonicalization/CanonicalJsonV1.ps1')
. (Join-Path $PSScriptRoot '../../../lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $PSScriptRoot '../../../lib/validation/PackageIdentity.ps1')

function Get-MIR4AuthorityMigrationRawSha256V1 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Test-MIR4ImmutableMigrationReceiptV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$ReceiptPath,
    [Parameter(Mandatory)][string]$ExpectedSha256,
    [Parameter(Mandatory)][string]$SchemaPath,
    [Parameter(Mandatory)][string]$Kind,
    [Parameter(Mandatory)][string]$DigestDomain,
    [string]$ErrorPrefix='mir4-authority-migration'
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo $ReceiptPath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[$ErrorPrefix-receipt-missing] $ReceiptPath" }
  if ((Get-MIR4AuthorityMigrationRawSha256V1 -Path $path) -cne $ExpectedSha256) {
    throw "[$ErrorPrefix-receipt-immutable-bytes] $ReceiptPath"
  }
  if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $ReceiptPath -SchemaPath $SchemaPath)) {
    throw "[$ErrorPrefix-receipt-schema] $ReceiptPath"
  }
  $receipt = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $ReceiptPath
  if ([string]$receipt.kind -cne $Kind) { throw "[$ErrorPrefix-receipt-kind] $ReceiptPath" }
  $digest = Get-MIR4CanonicalDigestV1 -Value $receipt -Domain $DigestDomain -OmitTopLevelDigest
  if ([string]$receipt.digest -cne $digest) { throw "[$ErrorPrefix-receipt-digest] $ReceiptPath" }
  foreach ($field in @('transition_gate','release_transition_authority')) {
    foreach ($property in $receipt.$field.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[$ErrorPrefix-release-firewall] $($ReceiptPath):$($field):$($property.Name)" }
    }
  }
  return $receipt
}

function New-MIR4AppendOnlyAuthorityMigrationReceiptV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Migration,
    [Parameter(Mandatory)]$Proof,
    [Parameter(Mandatory)]$Prior,
    [Parameter(Mandatory)][string]$ReceiptKind,
    [Parameter(Mandatory)][string]$ReceiptState,
    [Parameter(Mandatory)][string]$ReceiptPath,
    [Parameter(Mandatory)][string]$MigrationAuthorityPath,
    [Parameter(Mandatory)][string]$AssurancePath,
    [Parameter(Mandatory)][string]$Scope,
    [Parameter(Mandatory)][string]$EvolutionReason,
    [Parameter(Mandatory)][string]$DigestDomain,
    [Parameter(Mandatory)][Collections.IDictionary]$Parity,
    [Parameter(Mandatory)][string[]]$IntegrationPaths
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $predecessorPath = [string]$Migration.predecessor_receipt.path
  $predecessorSha256 = [string]$Migration.predecessor_receipt.sha256
  if ([string]$Prior.prior_receipt_path -cne $predecessorPath -or [string]$Prior.prior_receipt_sha256 -cne $predecessorSha256) {
    throw '[mir4-authority-migration-predecessor-chain]'
  }
  $predecessorFullPath = Join-Path $repo $predecessorPath
  if ((Get-MIR4AuthorityMigrationRawSha256V1 -Path $predecessorFullPath) -cne $predecessorSha256) {
    throw '[mir4-authority-migration-predecessor-bytes]'
  }

  $paths = @($IntegrationPaths) +
    @($Migration.path_map | Where-Object { [string]$_.final_path -cne $ReceiptPath } | ForEach-Object { [string]$_.final_path }) +
    @($Migration.compatibility_entrypoints | ForEach-Object { [string]$_.path })
  $components = @(
    foreach ($relativePath in @($paths | Sort-Object -Unique)) {
      $fullPath = Join-Path $repo $relativePath
      if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "[mir4-authority-migration-component-missing] $relativePath" }
      [ordered]@{path=$relativePath;sha256=(Get-MIR4PreFreezeFileSha256 -Path $fullPath -Mode 'canonical-text-v1');hash_mode='canonical-text-v1'}
    }
  )
  $componentPaths = @($components | ForEach-Object { [string]$_.path })
  $componentByPath = @{}
  foreach ($component in $components) { $componentByPath[[string]$component.path] = $component }

  $evolvedBindings = [Collections.Generic.List[object]]::new()
  $currentPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($entry in @($Prior.authority_hashes.GetEnumerator() | Sort-Object Key)) {
    $relativePath = [string]$entry.Key
    $fullPath = Join-Path $repo $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
    $mode = if ($Prior.authority_hash_modes.ContainsKey($relativePath)) { [string]$Prior.authority_hash_modes[$relativePath] } else { 'raw-bytes' }
    $actual = Get-MIR4PreFreezeFileSha256 -Path $fullPath -Mode $mode
    if ($actual -cne [string]$entry.Value) {
      $evolvedBindings.Add([ordered]@{
        path=$relativePath
        previous_sha256=[string]$entry.Value
        current_sha256=$actual
        hash_mode=$mode
        reason=$EvolutionReason
        scope=$Scope
        package_visible=$false
        release_authority=$false
      })
      [void]$currentPaths.Add($relativePath)
    }
  }
  foreach ($path in $componentPaths) { [void]$currentPaths.Add($path) }
  $currentAuthorities = @(
    foreach ($relativePath in @($currentPaths | Sort-Object)) {
      $mode = if ($Prior.authority_hash_modes.ContainsKey($relativePath)) { [string]$Prior.authority_hash_modes[$relativePath] }
        elseif ($componentByPath.ContainsKey($relativePath)) { [string]$componentByPath[$relativePath].hash_mode }
        else { 'raw-bytes' }
      $role = if ($relativePath -in $componentPaths -and $Prior.authority_hashes.ContainsKey($relativePath)) { 'migration-component-and-evolved-authority' }
        elseif ($relativePath -in $componentPaths) { 'migration-component' }
        else { 'evolved-authority' }
      [ordered]@{path=$relativePath;sha256=(Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo $relativePath) -Mode $mode);hash_mode=$mode;role=$role}
    }
  )
  $firewall = [ordered]@{source_freeze=$false;candidate_allocation=$false;production_signing=$false;seal=$false;promotion=$false;tagging=$false;publication=$false}
  $receipt = [ordered]@{
    schema=1
    kind=$ReceiptKind
    migration_id=[string]$Migration.migration_id
    state=$ReceiptState
    predecessor_receipt=[ordered]@{path=$predecessorPath;sha256=$predecessorSha256}
    predecessor_immutability=[ordered]@{path=$predecessorPath;sha256=$predecessorSha256;byte_length=(Get-Item -LiteralPath $predecessorFullPath).Length;raw_bytes_verified=$true}
    evolved_bindings=@($evolvedBindings)
    current_authorities=$currentAuthorities
    fixed_point_authority=[ordered]@{path='.mir/control/repository-fixed-point.json';sha256=(Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo '.mir/control/repository-fixed-point.json') -Mode 'canonical-text-v1');hash_mode='canonical-text-v1'}
    migration_authority=[ordered]@{path=$MigrationAuthorityPath;sha256=(Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo $MigrationAuthorityPath) -Mode 'canonical-text-v1');hash_mode='canonical-text-v1'}
    assurance_policy=[ordered]@{path=$AssurancePath;sha256=(Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo $AssurancePath) -Mode 'canonical-text-v1');hash_mode='canonical-text-v1';required_test_id=[string]$Proof.test_id}
    components=$components
    parity=$Parity
    activated_roots=@($Migration.activated_roots)
    package_source_sha256=Get-MIRPackageSourceFingerprint -RepoRoot $repo
    package_visible_delta=@()
    sunset=[ordered]@{state=[string]$Migration.sunset.state;compatibility_paths=@($Migration.compatibility_entrypoints | ForEach-Object { [string]$_.path });required_gates=@($Migration.sunset.required_gates)}
    transition_gate=$firewall
    release_transition_authority=$firewall
    digest=$null
  }
  $receipt.digest = Get-MIR4CanonicalDigestV1 -Value $receipt -Domain $DigestDomain -OmitTopLevelDigest
  return $receipt
}
