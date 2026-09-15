Set-StrictMode -Version Latest

$mir4ComposableSourceSuccessionRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4ComposableSourceSuccessionRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Get-MIR4CanonicalPackageAuthority -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4ComposableSourceSuccessionRoot 'tools/mir/application/package/PackageAuthority.ps1')
}

function Get-MIR4M41ToM42SourceSuccessionPolicy {
  # Keep this value function-local rather than in $script:.  The readiness
  # contract is dot-sourced by several independent entry points, and a
  # script-scoped variable would be resolved against the caller's script.
  return [ordered]@{
    readiness_path = 'governance/release/mir4-4.1-release-readiness-v1.json'
    readiness_schema = 'contracts/repository/mir4-4.1-release-readiness-v1.schema.json'
    source_freeze_path = 'releases/migrations/MIR4-M41-Source-Freeze-Authority-EvolutionV1.json'
    source_freeze_schema = 'contracts/repository/mir4-m41-source-freeze-authority-evolution-v1.schema.json'
    layout_authority_path = 'governance/repository/composable-source-layout-v1.json'
    layout_authority_schema = 'contracts/repository/mir4-composable-source-layout-authority-v1.schema.json'
    layout_proof_path = 'assurance/repository/composable-source-layout-v1.json'
    layout_proof_schema = 'contracts/repository/mir4-composable-source-layout-proof-policy-v1.schema.json'
    layout_receipt_path = 'assurance/repository/composable-source-layout-receipt-v1.json'
    layout_receipt_schema = 'contracts/repository/mir4-composable-source-layout-migration-v1.schema.json'
    output_path = 'assurance/repository/mir4-m41-to-m42-composable-source-succession-v1.json'
    output_schema = 'contracts/repository/mir4-m41-to-m42-composable-source-succession-v1.schema.json'
    historical_source_sha256 = '0DEDF851B388D8523110A2ABEDB3A7B2091E1CC119944F5EA7D4C1E7C01698DA'
    historical_authority_sha256 = '325CFA978C191C93E41F85D8F9AEB664B3A045D34D6721D647F8BE4E4F7F3CDB'
  }
}

function Read-MIR4M41ToM42SourceSuccessionJson {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$SchemaPath,
    [Parameter(Mandatory)][string]$Code
  )
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[$Code-missing] $RelativePath" }
  $raw = Get-Content -Raw -LiteralPath $path
  $schemaValid = $false
  try { $schemaValid = $raw | Test-Json -SchemaFile (Join-Path $RepoRoot $SchemaPath) -ErrorAction Stop } catch { $schemaValid = $false }
  if (-not $schemaValid) { throw "[$Code-schema] $RelativePath" }
  return $raw | ConvertFrom-Json -Depth 100 -DateKind String
}

function Assert-MIR4M41ToM42SourceSuccessionGate {
  param([Parameter(Mandatory)]$Gate,[Parameter(Mandatory)][string]$Code)
  if (-not [bool]$Gate.development_merge -or
      @($Gate.PSObject.Properties | Where-Object { [string]$_.Name -ne 'development_merge' -and [bool]$_.Value }).Count -ne 0) {
    throw "[$Code]"
  }
}

function Get-MIR4M41ToM42ComposableSourceSuccessionInputs {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [object]$HistoricalReadiness,
    [object]$HistoricalSourceFreeze,
    [object]$LayoutAuthority,
    [object]$LayoutProof,
    [object]$LayoutReceipt
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4M41ToM42SourceSuccessionPolicy
  if ($null -eq $HistoricalReadiness) {
    $HistoricalReadiness = Read-MIR4M41ToM42SourceSuccessionJson -RepoRoot $repo -RelativePath $policy.readiness_path -SchemaPath $policy.readiness_schema -Code 'mir4-m41-m42-succession-readiness'
  }
  if ($null -eq $HistoricalSourceFreeze) {
    $HistoricalSourceFreeze = Read-MIR4M41ToM42SourceSuccessionJson -RepoRoot $repo -RelativePath $policy.source_freeze_path -SchemaPath $policy.source_freeze_schema -Code 'mir4-m41-m42-succession-source-freeze'
  }
  if ($null -eq $LayoutAuthority) {
    $LayoutAuthority = Read-MIR4M41ToM42SourceSuccessionJson -RepoRoot $repo -RelativePath $policy.layout_authority_path -SchemaPath $policy.layout_authority_schema -Code 'mir4-m41-m42-succession-layout-authority'
  }
  if ($null -eq $LayoutProof) {
    $LayoutProof = Read-MIR4M41ToM42SourceSuccessionJson -RepoRoot $repo -RelativePath $policy.layout_proof_path -SchemaPath $policy.layout_proof_schema -Code 'mir4-m41-m42-succession-layout-proof'
  }
  if ($null -eq $LayoutReceipt) {
    $LayoutReceipt = Read-MIR4M41ToM42SourceSuccessionJson -RepoRoot $repo -RelativePath $policy.layout_receipt_path -SchemaPath $policy.layout_receipt_schema -Code 'mir4-m41-m42-succession-layout-receipt'
  }

  # Callers may supply records for negative and held-out tests.  They receive
  # the same exact-shape validation as records loaded from the checkout; a
  # recomputed self-hash is never a substitute for an admitted contract.
  foreach ($validation in @(
    [pscustomobject]@{record=$HistoricalReadiness; schema=$policy.readiness_schema; code='mir4-m41-m42-succession-readiness'},
    [pscustomobject]@{record=$HistoricalSourceFreeze; schema=$policy.source_freeze_schema; code='mir4-m41-m42-succession-source-freeze'},
    [pscustomobject]@{record=$LayoutAuthority; schema=$policy.layout_authority_schema; code='mir4-m41-m42-succession-layout-authority'},
    [pscustomobject]@{record=$LayoutProof; schema=$policy.layout_proof_schema; code='mir4-m41-m42-succession-layout-proof'},
    [pscustomobject]@{record=$LayoutReceipt; schema=$policy.layout_receipt_schema; code='mir4-m41-m42-succession-layout-receipt'}
  )) {
    $schemaValid = $false
    try { $schemaValid = (ConvertTo-MIR4BootstrapCanonicalJson -Value $validation.record) | Test-Json -SchemaFile (Join-Path $repo ([string]$validation.schema)) -ErrorAction Stop } catch { $schemaValid = $false }
    if (-not $schemaValid) {
      throw "[$($validation.code)-schema]"
    }
  }

  if ([string]$HistoricalReadiness.kind -cne 'MIR441ReleaseReadinessV1' -or
      [string]$HistoricalReadiness.package_source.predecessor_sha256 -cne $policy.historical_source_sha256 -or
      [string]$HistoricalReadiness.package_source.current_sha256 -cne $policy.historical_source_sha256 -or
      [string]$HistoricalReadiness.package_source.authority_record_sha256 -cne $policy.historical_authority_sha256) {
    throw '[mir4-m41-m42-succession-historical-readiness]'
  }
  if (-not (Test-MIR4BootstrapRecordHash -Record $HistoricalSourceFreeze) -or
      [string]$HistoricalSourceFreeze.kind -cne 'MIR4M41SourceFreezeAuthorityEvolutionV1' -or
      [string]$HistoricalSourceFreeze.package_source.predecessor_sha256 -cne $policy.historical_source_sha256 -or
      [string]$HistoricalSourceFreeze.package_source.current_sha256 -cne $policy.historical_source_sha256 -or
      [string]$HistoricalSourceFreeze.package_source.authority_record_sha256 -cne $policy.historical_authority_sha256 -or
      [string]$HistoricalSourceFreeze.package_source.current_sha256 -cne [string]$HistoricalReadiness.package_source.current_sha256 -or
      [string]$HistoricalSourceFreeze.package_source.authority_record_sha256 -cne [string]$HistoricalReadiness.package_source.authority_record_sha256) {
    throw '[mir4-m41-m42-succession-historical-lineage]'
  }
  $expectedLayoutScope = 'Replace the abbreviated and era-split live player-source layout with one package-shaped source root, explicit target adapters, explicit Factorio-1 compatibility code, and content-identity deduplication without changing materialized package bytes.'
  $expectedLayoutInvariants = @(
    'one-live-source-root', 'no-live-src-root', 'no-live-modern-or-legacy-lanes',
    'cross-checkout-source-bytes-pinned-to-lf', 'one-binding-per-target-output',
    'exact-predecessor-path-map', 'binary-safe-all-binding-predecessor-proof',
    'content-identical-inputs-share-one-physical-source', 'all-four-materialized-package-trees-unchanged',
    'historical-records-remain-immutable', 'one-current-package-writer', 'release-firewall'
  )
  $expectedLayoutChecks = @(
    'authority-and-proof-policy', 'v2-source-target-and-package-authority-schemas',
    'self-hashed-authorities', 'physical-source-set-equals-manifest', 'predecessor-path-bijection',
    'binary-safe-all-binding-predecessor-proof', 'deduplicated-current-source-identities',
    'no-retained-live-src-or-era-lanes', 'cross-checkout-source-byte-stability',
    'four-target-deterministic-materialization', 'exact-predecessor-package-content-parity',
    'historical-path-resolution-and-negative-counterexamples', 'release-firewall'
  )
  if ([string]$LayoutAuthority.kind -cne 'MIR4ComposableSourceLayoutAuthorityV1' -or
      [string]$LayoutAuthority.migration_id -cne 'MIR4-COMPOSABLE-SOURCE-LAYOUT-V1' -or
      [string]$LayoutAuthority.state -cne 'authorized-development-migration' -or
      [string]$LayoutAuthority.scope -cne $expectedLayoutScope -or
      [string]$LayoutAuthority.predecessor.branch -cne 'dev' -or
      [string]$LayoutAuthority.predecessor.commit -cne '92d563ada31e82430fbf25f639267b03a8a180d1' -or
      [string]$LayoutAuthority.predecessor.manifest -cne 'src/mod/package-source.json' -or
      [string]$LayoutAuthority.predecessor.manifest_record_sha256 -cne '8BDB2B9D3D63A5FBD49556609D6A7371B2BF11FA1D5F15BFD696E4C17EA3EF5E' -or
      (@($LayoutAuthority.required_invariants) -join '|') -cne ($expectedLayoutInvariants -join '|') -or
      @($LayoutAuthority.writers).Count -ne 1 -or
      [string]$LayoutAuthority.writers[0].path -cne 'tools/commands/mir4/Update-MIR4ComposableSourceLayoutAuthority.ps1' -or
      [string]$LayoutAuthority.rollback -cne 'Revert the exact source-layout work package to the recorded dev predecessor; do not recreate partial src/mod or target payload trees.') {
    throw '[mir4-m41-m42-succession-layout-authority]'
  }
  Assert-MIR4M41ToM42SourceSuccessionGate -Gate $LayoutAuthority.transition_gate -Code 'mir4-m41-m42-succession-layout-gate'
  if ([string]$LayoutProof.kind -cne 'MIR4ComposableSourceLayoutProofPolicyV1' -or
      [string]$LayoutProof.migration_id -cne 'MIR4-COMPOSABLE-SOURCE-LAYOUT-V1' -or
      [string]$LayoutProof.test_id -cne 'static.mir4-composable-source-layout-v1' -or
      [string]$LayoutProof.evidence_entrypoint -cne 'tests/mir4/Test-MIR4CanonicalSourceCompositionM4202.ps1' -or
      (@($LayoutProof.required_checks) -join '|') -cne ($expectedLayoutChecks -join '|') -or
      -not [bool]$LayoutProof.independent_exact_engine_required_for_gameplay_claims -or
      [bool]$LayoutProof.release_transition_authority) {
    throw '[mir4-m41-m42-succession-layout-proof]'
  }
  if (-not (Test-MIR4BootstrapRecordHash -Record $LayoutReceipt) -or
      [string]$LayoutReceipt.kind -cne 'MIR4ComposableSourceLayoutMigrationV1' -or
      [string]$LayoutReceipt.status -cne 'passed-byte-preserving-source-composition-cutover' -or
      [string]$LayoutReceipt.migration_id -cne 'MIR4-COMPOSABLE-SOURCE-LAYOUT-V1' -or
      [string]$LayoutReceipt.authority.sha256 -cne (Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $policy.layout_authority_path)) -or
      [string]$LayoutReceipt.proof_policy.sha256 -cne (Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $policy.layout_proof_path)) -or
      [string]$LayoutReceipt.current.source_root -cne 'source' -or
      [string]$LayoutReceipt.current.sole_writer -cne 'tools/mir/application/package/TargetMaterializer.ps1' -or
      -not [bool]$LayoutReceipt.invariants.package_bytes_unchanged -or
      [bool]$LayoutReceipt.invariants.historical_records_rewritten -or
      -not [bool]$LayoutReceipt.invariants.single_editable_source_root -or
      -not [bool]$LayoutReceipt.invariants.single_package_writer -or
      [bool]$LayoutReceipt.invariants.gameplay_semantics_changed) {
    throw '[mir4-m41-m42-succession-layout-receipt]'
  }
  Assert-MIR4M41ToM42SourceSuccessionGate -Gate $LayoutReceipt.transition_gate -Code 'mir4-m41-m42-succession-layout-receipt-gate'

  # Read the fixed-point authority directly.  RepositoryFixedPoint.ps1 keeps
  # its path in script scope, which is not reliable when its function is
  # imported through this independent release-readiness module.
  $fixedPointPath = Join-Path $repo '.mir/control/repository-fixed-point.json'
  if (-not (Test-Path -LiteralPath $fixedPointPath -PathType Leaf)) {
    throw '[mir4-m41-m42-succession-fixed-point]'
  }
  $fixedPointRaw = Get-Content -Raw -LiteralPath $fixedPointPath
  $fixedPointSchemaValid = $false
  try { $fixedPointSchemaValid = $fixedPointRaw | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-repository-fixed-point-v2.schema.json') -ErrorAction Stop } catch { $fixedPointSchemaValid = $false }
  if (-not $fixedPointSchemaValid) {
    throw '[mir4-m41-m42-succession-fixed-point-schema]'
  }
  $fixedPoint = $fixedPointRaw | ConvertFrom-Json -Depth 100 -DateKind String
  if ([int]$fixedPoint.schema -ne 2 -or
      [string]$fixedPoint.kind -cne 'MIR4RepositoryFixedPointV2' -or
      [string]$fixedPoint.state -cne 'MIR42-COMPOSABLE-SOURCE-LAYOUT' -or
      -not [bool]$fixedPoint.physical_cutover -or
      [bool]$fixedPoint.current_package_source_remains_authoritative -or
      @($fixedPoint.migration_sequence | Where-Object { [string]$_.migration_id -ceq 'MIR4-COMPOSABLE-SOURCE-LAYOUT-V1' -and [string]$_.state -ceq 'current-append-only-successor' }).Count -ne 1) {
    throw '[mir4-m41-m42-succession-fixed-point]'
  }
  $packageAuthority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $currentFingerprint = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
  if ([string]$LayoutReceipt.current.package_source_fingerprint_sha256 -cne $currentFingerprint -or
      [string]$LayoutReceipt.current.package_authority.path -cne 'targets/package-authority.json' -or
      [string]$LayoutReceipt.current.package_authority.sha256 -cne [string]$packageAuthority.record_sha256) {
    throw '[mir4-m41-m42-succession-current-package-authority]'
  }
  return [pscustomobject][ordered]@{
    historical_readiness = $HistoricalReadiness
    historical_source_freeze = $HistoricalSourceFreeze
    layout_authority = $LayoutAuthority
    layout_proof = $LayoutProof
    layout_receipt = $LayoutReceipt
    package_authority = $packageAuthority
    current_package_source_sha256 = $currentFingerprint
    fixed_point = $fixedPoint
  }
}

function New-MIR4M41ToM42ComposableSourceSuccession {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$RecordedAt = '2026-09-15T12:00:00+10:00'
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4M41ToM42SourceSuccessionPolicy
  $inputs = Get-MIR4M41ToM42ComposableSourceSuccessionInputs -RepoRoot $repo
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4M41ToM42ComposableSourceSuccessionV1'
    status = 'MIR41-HISTORICAL-SOURCE-FREEZE-PRESERVED-MIR42-COMPOSABLE-SUCCESSOR-VERIFIED'
    recorded_at = $RecordedAt
    historical = [pscustomobject][ordered]@{
      readiness = [pscustomobject][ordered]@{path=$policy.readiness_path;package_source_sha256=[string]$inputs.historical_readiness.package_source.current_sha256;authority_record_sha256=[string]$inputs.historical_readiness.package_source.authority_record_sha256}
      source_freeze = [pscustomobject][ordered]@{path=$policy.source_freeze_path;record_sha256=[string]$inputs.historical_source_freeze.record_sha256;package_source_sha256=[string]$inputs.historical_source_freeze.package_source.current_sha256;authority_record_sha256=[string]$inputs.historical_source_freeze.package_source.authority_record_sha256}
    }
    current = [pscustomobject][ordered]@{
      fixed_point = 'MIR42-COMPOSABLE-SOURCE-LAYOUT'
      layout_authority = [pscustomobject][ordered]@{path=$policy.layout_authority_path;sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $policy.layout_authority_path))}
      layout_proof = [pscustomobject][ordered]@{path=$policy.layout_proof_path;sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $policy.layout_proof_path))}
      layout_receipt = [pscustomobject][ordered]@{path=$policy.layout_receipt_path;record_sha256=[string]$inputs.layout_receipt.record_sha256}
      package_source_sha256 = [string]$inputs.current_package_source_sha256
      package_authority = [pscustomobject][ordered]@{path='targets/package-authority.json';record_sha256=[string]$inputs.package_authority.record_sha256}
    }
    invariants = [pscustomobject][ordered]@{
      historical_mir41_lineage_immutable = $true
      current_v2_composable_authority_proven = $true
      package_bytes_unchanged = $true
      current_mir41_release_operations_authorized = $false
      gameplay_semantics_changed = $false
    }
    transition_gate = [pscustomobject][ordered]@{development_merge=$true;private_build=$false;qualification=$false;technical_seal=$false;main_promotion=$false;version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
    record_sha256 = ''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

function Test-MIR4M41ToM42ComposableSourceSuccession {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [object]$SuccessionRecord
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4M41ToM42SourceSuccessionPolicy
  $expected = New-MIR4M41ToM42ComposableSourceSuccession -RepoRoot $repo
  if ($null -eq $SuccessionRecord) {
    $SuccessionRecord = Read-MIR4M41ToM42SourceSuccessionJson -RepoRoot $repo -RelativePath $policy.output_path -SchemaPath $policy.output_schema -Code 'mir4-m41-m42-succession-record'
  }
  if (-not (Test-MIR4BootstrapRecordHash -Record $SuccessionRecord) -or
      [string]$SuccessionRecord.kind -cne 'MIR4M41ToM42ComposableSourceSuccessionV1' -or
      [string]$SuccessionRecord.status -cne 'MIR41-HISTORICAL-SOURCE-FREEZE-PRESERVED-MIR42-COMPOSABLE-SUCCESSOR-VERIFIED') {
    throw '[mir4-m41-m42-succession-record-integrity]'
  }
  $recordSchemaValid = $false
  try { $recordSchemaValid = (ConvertTo-MIR4BootstrapCanonicalJson -Value $SuccessionRecord) | Test-Json -SchemaFile (Join-Path $repo $policy.output_schema) -ErrorAction Stop } catch { $recordSchemaValid = $false }
  if (-not $recordSchemaValid) {
    throw '[mir4-m41-m42-succession-record-schema]'
  }
  Assert-MIR4M41ToM42SourceSuccessionGate -Gate $SuccessionRecord.transition_gate -Code 'mir4-m41-m42-succession-release-firewall'
  if ([bool]$SuccessionRecord.transition_gate.private_build -or
      [bool]$SuccessionRecord.transition_gate.qualification -or
      [bool]$SuccessionRecord.transition_gate.technical_seal -or
      [bool]$SuccessionRecord.invariants.current_mir41_release_operations_authorized -or
      -not [bool]$SuccessionRecord.invariants.historical_mir41_lineage_immutable -or
      -not [bool]$SuccessionRecord.invariants.current_v2_composable_authority_proven -or
      -not [bool]$SuccessionRecord.invariants.package_bytes_unchanged -or
      [bool]$SuccessionRecord.invariants.gameplay_semantics_changed) {
    throw '[mir4-m41-m42-succession-release-firewall]'
  }
  $expectedJson = ConvertTo-MIR4BootstrapCanonicalJson -Value $expected
  $actualJson = ConvertTo-MIR4BootstrapCanonicalJson -Value $SuccessionRecord
  if ($actualJson -cne $expectedJson) { throw '[mir4-m41-m42-succession-record-stale]' }
  return [pscustomobject][ordered]@{
    status = 'passed-historical-mir41-to-current-mir42-composable-source-succession'
    historical_contract = $true
    current_release_operations_authorized = $false
    current_package_source_sha256 = [string]$SuccessionRecord.current.package_source_sha256
    current_package_authority_record_sha256 = [string]$SuccessionRecord.current.package_authority.record_sha256
    record_sha256 = [string]$SuccessionRecord.record_sha256
  }
}

function Assert-MIR441CurrentReleaseOperationAuthorized {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$Contract,[Parameter(Mandatory)][string]$Operation)
  $property = $Contract.transition_gate.PSObject.Properties[$Operation]
  if ($null -eq $property -or -not [bool]$property.Value) {
    throw "[mir441-current-release-operation-not-authorized] $Operation"
  }
}
