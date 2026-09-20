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

# V1 is immutable historical evidence for the 447/439 byte-preserving layout
# cutover.  It is deliberately not regenerated against later semantic source
# changes; V2 below is the live current-successor contract.
function Test-MIR4M41ToM42ComposableSourceSuccessionV1Historical {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4M41ToM42SourceSuccessionPolicy
  $record = Read-MIR4M41ToM42SourceSuccessionJson -RepoRoot $repo -RelativePath $policy.output_path -SchemaPath $policy.output_schema -Code 'mir4-m41-m42-succession-v1-historical'
  if (-not (Test-MIR4BootstrapRecordHash -Record $record) -or
      [string]$record.kind -cne 'MIR4M41ToM42ComposableSourceSuccessionV1' -or
      [string]$record.status -cne 'MIR41-HISTORICAL-SOURCE-FREEZE-PRESERVED-MIR42-COMPOSABLE-SUCCESSOR-VERIFIED' -or
      [string]$record.current.fixed_point -cne 'MIR42-COMPOSABLE-SOURCE-LAYOUT' -or
      [string]$record.current.package_source_sha256 -cne '7B0A39E3C5286624C8B6B272E32D1F6DE21F86FE91187E39AEF42FB80FCFC9ED' -or
      -not [bool]$record.invariants.package_bytes_unchanged -or [bool]$record.invariants.gameplay_semantics_changed) {
    throw '[mir4-m41-m42-succession-v1-historical-integrity]'
  }
  Assert-MIR4M41ToM42SourceSuccessionGate -Gate $record.transition_gate -Code 'mir4-m41-m42-succession-v1-historical-gate'
  return [pscustomobject][ordered]@{status='passed-historical-mir41-to-mir42-composable-source-layout';record_sha256=[string]$record.record_sha256;release_authority=$false}
}

function Get-MIR4M41ToM42ComposableSourceSuccessionV2Policy {
  return [ordered]@{
    output_path = 'assurance/repository/mir4-m41-to-m42-composable-source-succession-v2.json'
    output_schema = 'contracts/repository/mir4-m41-to-m42-composable-source-succession-v2.schema.json'
    v1_path = 'assurance/repository/mir4-m41-to-m42-composable-source-succession-v1.json'
    v1_schema = 'contracts/repository/mir4-m41-to-m42-composable-source-succession-v1.schema.json'
    layout_receipt_path = 'assurance/repository/composable-source-layout-receipt-v1.json'
    layout_receipt_schema = 'contracts/repository/mir4-composable-source-layout-migration-v1.schema.json'
    factorio_authority_path = 'governance/repository/factorio-one-source-convergence-v1.json'
    factorio_receipt_path = 'assurance/repository/factorio-one-source-convergence-v1.json'
    fixed_point_path = '.mir/control/repository-fixed-point.json'
    fixed_point_schema = 'contracts/repository/mir4-repository-fixed-point-v2.schema.json'
    tooling_inventory_path = 'governance/automation/mir4-command-inventory-v1.json'
  }
}

function Read-MIR4M41ToM42ComposableSourceSuccessionV2 {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4M41ToM42ComposableSourceSuccessionV2Policy
  return Read-MIR4M41ToM42SourceSuccessionJson -RepoRoot $repo -RelativePath $policy.output_path -SchemaPath $policy.output_schema -Code 'mir4-m41-m42-succession-v2-record'
}

function Get-MIR4M41ToM42ComposableSourceSuccessionV2ToolingInventoryBinding {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4M41ToM42ComposableSourceSuccessionV2Policy
  $path = Join-Path $repo $policy.tooling_inventory_path
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw '[mir4-m41-m42-succession-v2-tooling-inventory-missing]'
  }
  try {
    $inventory = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100 -DateKind String
  } catch {
    throw '[mir4-m41-m42-succession-v2-tooling-inventory-json]'
  }
  if ([int]$inventory.schema -ne 1 -or
      [string]$inventory.kind -cne 'MIR4CommandInventoryV1' -or
      [string]$inventory.state -cne 'M42-01-CANONICAL' -or
      [string]$inventory.digest -notmatch '^sha256:[a-f0-9]{64}$' -or
      [int]$inventory.command_count -ne 85 -or
      [int]$inventory.summary.unknown -ne 0 -or
      [int]$inventory.summary.duplicate_command_keys -ne 0) {
    throw '[mir4-m41-m42-succession-v2-tooling-inventory-invariants]'
  }
  return [pscustomobject][ordered]@{
    path = $policy.tooling_inventory_path
    sha256 = Get-MIR4BootstrapTextSha256 -Path $path
    hash_mode = 'canonical-text-v1'
    digest = [string]$inventory.digest
    command_count = [int]$inventory.command_count
    unknown = [int]$inventory.summary.unknown
    duplicate_command_keys = [int]$inventory.summary.duplicate_command_keys
  }
}

function Get-MIR4M41ToM42ComposableSourceSuccessionV2Inputs {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4M41ToM42ComposableSourceSuccessionV2Policy
  . (Join-Path $repo 'tools/mir/application/package/FactorioOneSourceConvergenceAuthority.ps1')

  $v1 = Read-MIR4M41ToM42SourceSuccessionJson -RepoRoot $repo -RelativePath $policy.v1_path -SchemaPath $policy.v1_schema -Code 'mir4-m41-m42-succession-v2-v1'
  Test-MIR4M41ToM42ComposableSourceSuccessionV1Historical -RepoRoot $repo | Out-Null
  $layout = Read-MIR4M41ToM42SourceSuccessionJson -RepoRoot $repo -RelativePath $policy.layout_receipt_path -SchemaPath $policy.layout_receipt_schema -Code 'mir4-m41-m42-succession-v2-layout'
  if (-not (Test-MIR4BootstrapRecordHash -Record $layout) -or [string]$layout.record_sha256 -cne [string]$v1.current.layout_receipt.record_sha256) {
    throw '[mir4-m41-m42-succession-v2-layout-binding]'
  }
  $factorio = Read-MIR4FactorioOneSourceConvergenceReceipt -RepoRoot $repo
  Assert-MIR4FactorioOneSourceConvergenceReceiptCurrent -RepoRoot $repo -Receipt $factorio | Out-Null
  $current = Get-MIR4FactorioOneSourceConvergenceCurrentAuthority -RepoRoot $repo
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $factorio.current) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $current)) {
    throw '[mir4-m41-m42-succession-v2-factorio-current-binding]'
  }
  $fixedPointRaw = Get-Content -Raw -LiteralPath (Join-Path $repo $policy.fixed_point_path)
  $fixedPointValid = $false
  try { $fixedPointValid = [bool]($fixedPointRaw | Test-Json -SchemaFile (Join-Path $repo $policy.fixed_point_schema) -ErrorAction Stop) } catch { $fixedPointValid = $false }
  if (-not $fixedPointValid) { throw '[mir4-m41-m42-succession-v2-fixed-point-schema]' }
  $fixedPoint = $fixedPointRaw | ConvertFrom-Json -Depth 100 -DateKind String
  if ([string]$fixedPoint.state -cne 'MIR42-FACTORIO-ONE-SOURCE-CONVERGENCE' -or
      @($fixedPoint.migration_sequence | Where-Object { [string]$_.migration_id -ceq 'MIR4-M41-TO-M42-COMPOSABLE-SOURCE-SUCCESSION-V2' -and [string]$_.state -ceq 'current-append-only-successor' }).Count -ne 1) {
    throw '[mir4-m41-m42-succession-v2-fixed-point]'
  }
  $toolingInventory = Get-MIR4M41ToM42ComposableSourceSuccessionV2ToolingInventoryBinding -RepoRoot $repo
  return [pscustomobject][ordered]@{v1=$v1;layout=$layout;factorio=$factorio;current=$current;fixed_point=$fixedPoint;tooling_inventory=$toolingInventory}
}

function New-MIR4M41ToM42ComposableSourceSuccessionV2 {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[string]$RecordedAt='2026-09-16T00:43:00+10:00')
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4M41ToM42ComposableSourceSuccessionV2Policy
  $inputs = Get-MIR4M41ToM42ComposableSourceSuccessionV2Inputs -RepoRoot $repo
  $record = [pscustomobject][ordered]@{
    schema = 2
    kind = 'MIR4M41ToM42ComposableSourceSuccessionV2'
    status = 'MIR41-HISTORICAL-SOURCE-FREEZE-PRESERVED-MIR42-FACTORIO-ONE-SOURCE-SUCCESSOR-VERIFIED'
    recorded_at = $RecordedAt
    historical = [pscustomobject][ordered]@{path=$policy.v1_path;kind=[string]$inputs.v1.kind;record_sha256=[string]$inputs.v1.record_sha256}
    layout_successor = [pscustomobject][ordered]@{path=$policy.layout_receipt_path;kind=[string]$inputs.layout.kind;record_sha256=[string]$inputs.layout.record_sha256}
    factorio_one_successor = [pscustomobject][ordered]@{
      authority = [pscustomobject][ordered]@{path=$policy.factorio_authority_path;sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $policy.factorio_authority_path))}
      receipt = [pscustomobject][ordered]@{path=$policy.factorio_receipt_path;kind=[string]$inputs.factorio.kind;record_sha256=[string]$inputs.factorio.record_sha256}
    }
    current = [pscustomobject][ordered]@{
      fixed_point = 'MIR42-FACTORIO-ONE-SOURCE-CONVERGENCE'
      package_source_sha256 = [string]$inputs.current.package_source_fingerprint_sha256
      package_authority = [pscustomobject][ordered]@{path=[string]$inputs.current.package_authority.path;kind=[string]$inputs.current.package_authority.kind;record_sha256=[string]$inputs.current.package_authority.record_sha256}
      tooling_inventory = $inputs.tooling_inventory
    }
    invariants = [pscustomobject][ordered]@{
      historical_mir41_lineage_immutable = $true
      v1_layout_receipt_immutable = $true
      factorio_one_static_convergence_proven = $true
      package_bytes_unchanged = $false
      factorio_two_presentation_content_changed = $true
      factorio_two_executable_content_preserved = $true
      factorio_one_semantic_content_changed = $true
      factorio_one_exact_engine_proof_required = $true
      current_mir41_release_operations_authorized = $false
    }
    transition_gate = [pscustomobject][ordered]@{development_merge=$true;private_build=$false;qualification=$false;technical_seal=$false;main_promotion=$false;version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
    record_sha256 = ''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  $json = ConvertTo-MIR4BootstrapCanonicalJson -Value $record
  if (-not ($json | Test-Json -SchemaFile (Join-Path $repo $policy.output_schema))) { throw '[mir4-m41-m42-succession-v2-schema]' }
  return $record
}

function Test-MIR4M41ToM42ComposableSourceSuccessionV2 {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[object]$SuccessionRecord)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4M41ToM42ComposableSourceSuccessionV2Policy
  if ($null -eq $SuccessionRecord) { $SuccessionRecord = Read-MIR4M41ToM42ComposableSourceSuccessionV2 -RepoRoot $repo }
  $schemaValid = $false
  try { $schemaValid = [bool]((ConvertTo-MIR4BootstrapCanonicalJson -Value $SuccessionRecord) | Test-Json -SchemaFile (Join-Path $repo $policy.output_schema) -ErrorAction Stop) } catch { $schemaValid = $false }
  if (-not $schemaValid) { throw '[mir4-m41-m42-succession-v2-schema]' }
  if (-not (Test-MIR4BootstrapRecordHash -Record $SuccessionRecord)) { throw '[mir4-m41-m42-succession-v2-hash]' }
  $expected = New-MIR4M41ToM42ComposableSourceSuccessionV2 -RepoRoot $repo -RecordedAt ([string]$SuccessionRecord.recorded_at)
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $SuccessionRecord) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $expected)) { throw '[mir4-m41-m42-succession-v2-stale]' }
  Assert-MIR4M41ToM42SourceSuccessionGate -Gate $SuccessionRecord.transition_gate -Code 'mir4-m41-m42-succession-v2-gate'
  return [pscustomobject][ordered]@{status='passed-historical-mir41-to-current-mir42-factorio-one-source-succession';current_release_operations_authorized=$false;factorio_one_exact_engine_proof_required=$true;current_package_source_sha256=[string]$SuccessionRecord.current.package_source_sha256;tooling_inventory_digest=[string]$SuccessionRecord.current.tooling_inventory.digest;record_sha256=[string]$SuccessionRecord.record_sha256}
}

# V3 is the append-only successor for the schema-3 progression port. V2 is
# frozen Factorio-1 convergence evidence and is deliberately not regenerated
# against the later semantic package identities.
function Get-MIR4M41ToM42ComposableSourceSuccessionV3Policy {
  return [ordered]@{
    output_path = 'assurance/repository/mir4-m41-to-m42-composable-source-succession-v3.json'
    output_schema = 'contracts/repository/mir4-m41-to-m42-composable-source-succession-v3.schema.json'
    v2_path = 'assurance/repository/mir4-m41-to-m42-composable-source-succession-v2.json'
    v2_schema = 'contracts/repository/mir4-m41-to-m42-composable-source-succession-v2.schema.json'
    presentation_path = 'spec/distribution/mir4-current-package-presentation-v5.json'
    presentation_schema = 'spec/schemas/mir4-current-package-presentation-v5.schema.json'
    pre_freeze_tooling_inventory_predecessor_sha256 = 'CC28AA34B139C0B082BAF07E81829D797F4A2B303AA31A7C3A6FD3EC526F834A'
    pre_freeze_evolved_bindings = @(
      # These are the exact values reached by the frozen M42-02 chain before
      # the source-cutover/progression successor. They are an explicit finite
      # transition list, not an inference from arbitrary later checkout bytes.
      # Every row remains package- and release-excluded.
      [pscustomobject][ordered]@{path='.mir/assurance.json';previous_sha256='074DA277D4C9BCF3B1A6505047F724154807C21A44C08E43B4F89E0CF8A56F58';current_sha256='5116211C95BE060474B091C50971637C337EA4015B9312D99BE4C825CE56EAA2'}
      [pscustomobject][ordered]@{path='.mir/control/paths.yml';previous_sha256='EC4C705D22C218AF7E2B838035F1D974D3850BDD477DC44E947329B12F6CD85B';current_sha256='59138DF52AB407F67E5B4CA1D390BA46F1F5820F857052F6706B2408DC8C1BE7'}
      [pscustomobject][ordered]@{path='.mir/modules.yml';previous_sha256='506E67864097D9A9D228DEBBF157B1D113687B2A5EAC24A8433A7F02C7F6C9EA';current_sha256='9CB3EDA28BC47D994972D88AC5F82E2AFFFA3B7754746FC612638C6B605274E8'}
      [pscustomobject][ordered]@{path='assurance/catalog/tests.json';previous_sha256='0AAD6F171A47F7E5B69FDD325FAE4BAAE3A94C0C44616683416066D8A7C24699';current_sha256='C0F358186B2B770A376BD881F211EE072963A2F3360E7AD64D0C0F9C1125FF7D'}
      [pscustomobject][ordered]@{path='docs/architecture/module-boundaries.md';previous_sha256='99CBFC8FAEBDDA28AC51739BD5F69E5AB73B9ECEBEAE540354116B276560275E';current_sha256='8347D3E5191A1D72F222D316ABD6A08AC3408C9AF75CBA4A8B418C4F78AAD665'}
      [pscustomobject][ordered]@{path='tests/architecture/Test-MIRArchitecture.ps1';previous_sha256='60BA9050BBBAC31114C06B699708B42EBAE8680452D299D3953185FB2AB93FFB';current_sha256='3DD1DD2350ECB04CB92AC9B8CDBD76586E30C9012AA521A96B3A8A5647AB3C8B'}
      [pscustomobject][ordered]@{path='tests/mir4/Test-MIR4DocumentationCutoverM4105B.ps1';previous_sha256='4E538FF77E49BEA7AB3555ED7F4FC8113AFB5BD82374E5BF055F65ECB951AE47';current_sha256='A0F90FA14FF771510142730E7E9AFBAF33C7E54D128EB21DABCC56B2F8EEF8A0'}
      [pscustomobject][ordered]@{path='tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1';previous_sha256='57F0F8E10EDECFFE274B8E79CFED750527957133AD24AF29895B27F893273F74';current_sha256='8ECA00F8BD5B3D98806B3E260478C77D0D21CD90D2543DE633C88D8F1FEA6747'}
      [pscustomobject][ordered]@{path='tests/repository/Test-MIR4RepositoryFixedPoint.ps1';previous_sha256='D51678A896BB76B8F26BDA7DDA0D31CEE44146C319D087F81510EFE7BDE98FC6';current_sha256='9EE3FB7554EB994E046B99FFD8AC4E13AB8889E52523C524A92962BB3BEBC388'}
      [pscustomobject][ordered]@{path='tests/tooling/Test-MIRAssurance.ps1';previous_sha256='01CBEFF991124FF1D2E41F02D63BF325F3F3C31F4EF5CC2660B9C22C28CE557B';current_sha256='4353D89895DF35CAC6CC1109A1FD4070777F26160CBDCD72E99AEEE9D7B7DBED'}
      [pscustomobject][ordered]@{path='validation/tests.yml';previous_sha256='CA25A4BCA78510C00C996B802CFE79CC2092248A591240BAD00797C6CAC1C421';current_sha256='B6D415F82816BC100D817A518A3FAC09A190DE1CBAA571F82A89753310F8D004'}
      [pscustomobject][ordered]@{path='tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1';previous_sha256='0E8F9490D8FDD8245597A2CB09E4ABC50BDC8371F605521C0ADA4CFBA852EEC8';current_sha256='5020935FC3AC85888232CC0756AE20718F9FB30B4611E009E5E3415897A962EC'}
      [pscustomobject][ordered]@{path='tools/lib/mir4/pre-freeze-release/ReleaseDoctor.ps1';previous_sha256='68B7621F6382186D5A40C1AAAB9775CF33AB380AC29B250A25468F6BECBF7089';current_sha256='F74A35E850047648E96D759A0E62F5E7B744FDB1248E05EB55302D808D82437D'}
    )
  }
}

function Get-MIR4M41ToM42ComposableSourceSuccessionV2Historical {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4M41ToM42ComposableSourceSuccessionV3Policy
  $record = Read-MIR4M41ToM42SourceSuccessionJson -RepoRoot $repo -RelativePath $policy.v2_path -SchemaPath $policy.v2_schema -Code 'mir4-m41-m42-succession-v2-historical'
  if (-not (Test-MIR4BootstrapRecordHash -Record $record) -or
      [string]$record.kind -cne 'MIR4M41ToM42ComposableSourceSuccessionV2' -or
      [string]$record.record_sha256 -cne '26D782754CD2FB05715279C9A5AAC0847C54E0AA639839FCCF906D069059FE26' -or
      [string]$record.current.package_source_sha256 -cne '909D8F0F1CA8B59E42CFBED5C854734B57DE40308D2E05752BD8694E1EC1821E' -or
      -not [bool]$record.invariants.factorio_two_executable_content_preserved -or
      [bool]$record.invariants.current_mir41_release_operations_authorized) {
    throw '[mir4-m41-m42-succession-v2-historical-integrity]'
  }
  Assert-MIR4M41ToM42SourceSuccessionGate -Gate $record.transition_gate -Code 'mir4-m41-m42-succession-v2-historical-gate'
  return $record
}

function Get-MIR4M41ToM42ComposableSourceSuccessionV3EvolvedBindings {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
  $policy = Get-MIR4M41ToM42ComposableSourceSuccessionV3Policy
  $bindings = [Collections.Generic.List[object]]::new()
  foreach($spec in @($policy.pre_freeze_evolved_bindings)) {
    $path = Join-Path $repo ([string]$spec.path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "[mir4-m41-m42-succession-v3-pre-freeze-binding-missing] $($spec.path)"
    }
    $currentSha256 = Get-MIR4BootstrapTextSha256 -Path $path
    if ($currentSha256 -cne [string]$spec.current_sha256) {
      throw "[mir4-m41-m42-succession-v3-pre-freeze-binding-unqualified] $($spec.path)"
    }
    $bindings.Add([pscustomobject][ordered]@{
      path = [string]$spec.path
      previous_sha256 = [string]$spec.previous_sha256
      current_sha256 = $currentSha256
      hash_mode = 'canonical-text-v1'
      package_visible = $false
      release_authority = $false
    })
  }
  return @($bindings)
}

function New-MIR4M41ToM42ComposableSourceSuccessionV3 {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$RepoRoot,[string]$RecordedAt='2026-09-16T12:00:00+10:00')
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  . (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
  . (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
  $policy = Get-MIR4M41ToM42ComposableSourceSuccessionV3Policy
  $v2 = Get-MIR4M41ToM42ComposableSourceSuccessionV2Historical -RepoRoot $repo
  $v5 = Get-MIR4CurrentPackagePresentationV5 -RepoRoot $repo
  $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $evolvedBindings = Get-MIR4M41ToM42ComposableSourceSuccessionV3EvolvedBindings -RepoRoot $repo
  $toolingInventory = Get-MIR4M41ToM42ComposableSourceSuccessionV2ToolingInventoryBinding -RepoRoot $repo
  $record = [pscustomobject][ordered]@{
    schema=3;kind='MIR4M41ToM42ComposableSourceSuccessionV3';status='MIR41-HISTORICAL-LINEAGE-PRESERVED-MIR42-PROGRESSION-SOURCE-SUCCESSOR-STATIC-VERIFIED';recorded_at=$RecordedAt
    predecessor=[pscustomobject][ordered]@{path=$policy.v2_path;kind=[string]$v2.kind;record_sha256=[string]$v2.record_sha256;immutable_historical_receipt=$true}
    progression_package_presentation=[pscustomobject][ordered]@{path=$policy.presentation_path;kind=[string]$v5.kind;record_sha256=[string]$v5.record_sha256}
    current=[pscustomobject][ordered]@{package_source_sha256=[string]$v5.package_source.fingerprint_sha256;package_authority=[pscustomobject][ordered]@{path='targets/package-authority.json';kind=[string]$authority.kind;record_sha256=[string]$authority.record_sha256};tooling_inventory_predecessor_sha256=[string]$policy.pre_freeze_tooling_inventory_predecessor_sha256;tooling_inventory=$toolingInventory;f210_f200_exact_engine_qualification_required=$true;f110_f100_progression_capability_nonclaim=$true}
    evolved_bindings=@($evolvedBindings)
    invariants=[pscustomobject][ordered]@{historical_mir41_lineage_immutable=$true;v2_factorio_one_convergence_immutable=$true;v4_package_presentation_immutable=$true;progression_semantic_change_declared=$true;f210_f200_exact_engine_qualification_required=$true;f110_f100_progression_capability_omitted_nonclaim=$true;current_mir41_release_operations_authorized=$false}
    transition_gate=[pscustomobject][ordered]@{development_merge=$true;private_build=$false;qualification=$false;technical_seal=$false;main_promotion=$false;version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
    record_sha256=''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  if (-not ((ConvertTo-MIR4BootstrapCanonicalJson -Value $record) | Test-Json -SchemaFile (Join-Path $repo $policy.output_schema))) { throw '[mir4-m41-m42-succession-v3-schema]' }
  return $record
}

function Get-MIR4M41ToM42ComposableSourceSuccessionV3 {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4M41ToM42ComposableSourceSuccessionV3Policy
  $raw = Get-Content -Raw -LiteralPath (Join-Path $repo $policy.output_path)
  $record = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not ((ConvertTo-MIR4BootstrapCanonicalJson -Value $record) | Test-Json -SchemaFile (Join-Path $repo $policy.output_schema)) -or -not (Test-MIR4BootstrapRecordHash -Record $record) -or $raw -cne ((ConvertTo-MIR4BootstrapCanonicalJson -Value $record) + [char]10)) { throw '[mir4-m41-m42-succession-v3-integrity]' }
  # V3 is immutable evidence for the progression successor.  It must not be
  # regenerated against later control-plane changes; those changes belong to
  # V4 and bind V3 by this exact record identity.
  if ([string]$record.kind -cne 'MIR4M41ToM42ComposableSourceSuccessionV3' -or
      [string]$record.status -cne 'MIR41-HISTORICAL-LINEAGE-PRESERVED-MIR42-PROGRESSION-SOURCE-SUCCESSOR-STATIC-VERIFIED' -or
      [string]$record.record_sha256 -cne '387ECBA18CB90C6F92D6C4D8FA76EF54E85FB21278F93EFD455A55CA7998FA53' -or
      [string]$record.predecessor.path -cne $policy.v2_path -or
      [string]$record.predecessor.kind -cne 'MIR4M41ToM42ComposableSourceSuccessionV2' -or
      [string]$record.predecessor.record_sha256 -cne '26D782754CD2FB05715279C9A5AAC0847C54E0AA639839FCCF906D069059FE26' -or
      -not [bool]$record.predecessor.immutable_historical_receipt -or
      [string]$record.progression_package_presentation.path -cne $policy.presentation_path -or
      [string]$record.progression_package_presentation.kind -cne 'MIR4CurrentPackagePresentationV5' -or
      [string]$record.progression_package_presentation.record_sha256 -cne 'D2C73297B4A7BA404B13EEC0AB29C5CDE56357F04ED4B48C9B1099F2F2DA7470' -or
      [string]$record.current.package_source_sha256 -cne 'A476DDAFA5AB62BD6AEC69054E1A162C570DDB946520AF9234FC8FE0D79BEC2F') {
    throw '[mir4-m41-m42-succession-v3-historical-integrity]'
  }
  Assert-MIR4M41ToM42SourceSuccessionGate -Gate $record.transition_gate -Code 'mir4-m41-m42-succession-v3-gate'
  return $record
}

function Test-MIR4M41ToM42ComposableSourceSuccessionV3 {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$RepoRoot,[object]$SuccessionRecord)
  if ($null -eq $SuccessionRecord) { $SuccessionRecord = Get-MIR4M41ToM42ComposableSourceSuccessionV3 -RepoRoot $RepoRoot }
  if (-not (Test-MIR4BootstrapRecordHash -Record $SuccessionRecord) -or
      [string]$SuccessionRecord.record_sha256 -cne '387ECBA18CB90C6F92D6C4D8FA76EF54E85FB21278F93EFD455A55CA7998FA53') {
    throw '[mir4-m41-m42-succession-v3-historical-integrity]'
  }
  Assert-MIR4M41ToM42SourceSuccessionGate -Gate $SuccessionRecord.transition_gate -Code 'mir4-m41-m42-succession-v3-gate'
  return [pscustomobject][ordered]@{status='passed-historical-mir41-to-current-mir42-progression-source-succession';current_release_operations_authorized=$false;factorio_one_exact_engine_proof_required=$true;current_package_source_sha256=[string]$SuccessionRecord.current.package_source_sha256;record_sha256=[string]$SuccessionRecord.record_sha256}
}

# V4 is the append-only proof-input/control-plane successor. It preserves V3
# byte-for-byte while binding the typed proof-input repair and its exact
# package-excluded control-plane identities to the unchanged V5 package.
function Get-MIR4M41ToM42ComposableSourceSuccessionV4Policy {
  return [ordered]@{
    output_path = 'assurance/repository/mir4-m41-to-m42-composable-source-succession-v4.json'
    output_schema = 'contracts/repository/mir4-m41-to-m42-composable-source-succession-v4.schema.json'
    v3_path = 'assurance/repository/mir4-m41-to-m42-composable-source-succession-v3.json'
    v3_schema = 'contracts/repository/mir4-m41-to-m42-composable-source-succession-v3.schema.json'
    presentation_path = 'spec/distribution/mir4-current-package-presentation-v5.json'
    presentation_schema = 'spec/schemas/mir4-current-package-presentation-v5.schema.json'
    v3_record_sha256 = '387ECBA18CB90C6F92D6C4D8FA76EF54E85FB21278F93EFD455A55CA7998FA53'
    v3_tooling_inventory_sha256 = '59F98A68D36A085DEDF47B9B60AA8C4157BF6BB9A7A0D3FB4331B0DC772BF35D'
    control_plane_bindings = @(
      [pscustomobject][ordered]@{path='.github/workflows/release-candidate.yml';previous_sha256='E8D63D687601D1889CAB08619FF08897E92416BF57B56FD87A7268F2B99D49DC'}
      [pscustomobject][ordered]@{path='.mir/assurance.json';previous_sha256='5116211C95BE060474B091C50971637C337EA4015B9312D99BE4C825CE56EAA2'}
      [pscustomobject][ordered]@{path='.mir/compatibility.yml';previous_sha256='72F8024B9E3DC448377BDADCEC84BB4E7808FBE5DD7EE46303BCCC4144191095'}
      [pscustomobject][ordered]@{path='.mir/test-impact.yml';previous_sha256='927BB6AF61D261D19A9A573596198EDC529FDD3FA3E4BAB16EFA709B54B54170'}
      [pscustomobject][ordered]@{path='assurance/catalog/tests.json';previous_sha256='C0F358186B2B770A376BD881F211EE072963A2F3360E7AD64D0C0F9C1125FF7D'}
      [pscustomobject][ordered]@{path='docs/compatibility/targets/corrundum.md';previous_sha256='998A27579611C67B240C07EA0809D08793063CB3EBE451704AC233123D09B7D9'}
      [pscustomobject][ordered]@{path='docs/compatibility/targets/cubium.md';previous_sha256='EA1AC5710D489076B49E9769A62AC8D05EB879AE15AD0458B45ADC1DEF391621'}
      [pscustomobject][ordered]@{path='tests/package/Test-MIRContextPackage.ps1';previous_sha256='133CB8A6D32B222AC3F5A9515F4D67B253170D27F3FD899E8CC29768D7E00231'}
      [pscustomobject][ordered]@{path='tests/repository/Test-MIR4DevelopmentContracts.ps1';previous_sha256='FD2132D3430AE8ED703B23308DE3E8A3B7C360176F14EE199E7DF75EB7095FA7'}
      [pscustomobject][ordered]@{path='tests/tooling/Test-MIRAssurance.ps1';previous_sha256='4353D89895DF35CAC6CC1109A1FD4070777F26160CBDCD72E99AEEE9D7B7DBED'}
      [pscustomobject][ordered]@{path='tests/tooling/support/MIRAssuranceSelfTest.ps1';previous_sha256='E4ABF9B8685BEF1ADDF0F64FDF41BF13E5E170254264102B942C8A08C4AB37C7'}
      [pscustomobject][ordered]@{path='tools/lib/assurance/Domains.ps1';previous_sha256='28DC1A8F9369D81FEDFCBFB68FE0998CC94A575EED2321B9510AC8D6C457BBAD'}
      [pscustomobject][ordered]@{path='tools/lib/assurance/evidence/Fingerprints.ps1';previous_sha256='69DC0201E97C2E3B4A6027313365625DC1F708295C7840B41FD0A24B771E0D73'}
      [pscustomobject][ordered]@{path='tools/lib/validation/runner/StaticCompilerDiagnostics.ps1';previous_sha256='A144C5ACF98BBAFF6EB61D6A4FCE7712F9E2FBB4C7B78FB43159742210B6F476'}
      [pscustomobject][ordered]@{path='validation/scenarios/local-2.1.json';previous_sha256='912AA8D22C2E5E140340866535CD05729D06C6A09A107B619CDE758DE1F37B46'}
      [pscustomobject][ordered]@{path='validation/tests.yml';previous_sha256='B6D415F82816BC100D817A518A3FAC09A190DE1CBAA571F82A89753310F8D004'}
    )
  }
}

function Get-MIR4M41ToM42ComposableSourceSuccessionV4ExpectedRecordSha256 {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4M41ToM42ComposableSourceSuccessionV4Policy
  $schema = Get-Content -Raw -LiteralPath (Join-Path $repo $policy.output_schema) |
    ConvertFrom-Json -Depth 100 -DateKind String
  $expected = [string]$schema.properties.record_sha256.const
  if ($expected -cnotmatch '^[A-F0-9]{64}$') {
    throw '[mir4-m41-m42-succession-v4-schema-record-identity]'
  }
  return $expected
}

function Get-MIR4M41ToM42ComposableSourceSuccessionV4EvolvedBindings {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
  $policy = Get-MIR4M41ToM42ComposableSourceSuccessionV4Policy
  $bindings = [Collections.Generic.List[object]]::new()
  foreach ($spec in @($policy.control_plane_bindings)) {
    $path = Join-Path $repo ([string]$spec.path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "[mir4-m41-m42-succession-v4-control-plane-binding-missing] $($spec.path)"
    }
    $currentSha256 = Get-MIR4BootstrapTextSha256 -Path $path
    if ($currentSha256 -ceq [string]$spec.previous_sha256) {
      throw "[mir4-m41-m42-succession-v4-control-plane-binding-unchanged] $($spec.path)"
    }
    $bindings.Add([pscustomobject][ordered]@{
      path = [string]$spec.path
      previous_sha256 = [string]$spec.previous_sha256
      current_sha256 = $currentSha256
      hash_mode = 'canonical-text-v1'
      package_visible = $false
      release_authority = $false
    })
  }
  return @($bindings)
}

function Assert-MIR4M41ToM42ComposableSourceSuccessionV4CurrentBindings {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][object]$Record,
    [object[]]$CurrentEvolvedBindings,
    [object]$CurrentToolingInventory
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $evolvedBindings = if ($PSBoundParameters.ContainsKey('CurrentEvolvedBindings')) {
    @($CurrentEvolvedBindings)
  } else {
    @(Get-MIR4M41ToM42ComposableSourceSuccessionV4EvolvedBindings -RepoRoot $repo)
  }
  $toolingInventory = if ($PSBoundParameters.ContainsKey('CurrentToolingInventory')) {
    $CurrentToolingInventory
  } else {
    Get-MIR4M41ToM42ComposableSourceSuccessionV2ToolingInventoryBinding -RepoRoot $repo
  }
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value @($Record.evolved_bindings)) -cne
      (ConvertTo-MIR4BootstrapCanonicalJson -Value @($evolvedBindings))) {
    throw '[mir4-m41-m42-succession-v4-evolved-bindings-current]'
  }
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $Record.current.tooling_inventory) -cne
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $toolingInventory)) {
    throw '[mir4-m41-m42-succession-v4-tooling-inventory-current]'
  }
  return $true
}

function New-MIR4M41ToM42ComposableSourceSuccessionV4 {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$RepoRoot,[string]$RecordedAt='2026-09-16T12:30:00+10:00')
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  . (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
  . (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
  $policy = Get-MIR4M41ToM42ComposableSourceSuccessionV4Policy
  $v3 = Get-MIR4M41ToM42ComposableSourceSuccessionV3 -RepoRoot $repo
  $v5 = Get-MIR4CurrentPackagePresentationV5 -RepoRoot $repo
  $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $toolingInventory = Get-MIR4M41ToM42ComposableSourceSuccessionV2ToolingInventoryBinding -RepoRoot $repo
  $evolvedBindings = Get-MIR4M41ToM42ComposableSourceSuccessionV4EvolvedBindings -RepoRoot $repo
  $record = [pscustomobject][ordered]@{
    schema=4;kind='MIR4M41ToM42ComposableSourceSuccessionV4';status='MIR41-HISTORICAL-LINEAGE-PRESERVED-MIR42-PROOF-INPUT-CONTROL-PLANE-SUCCESSOR-STATIC-VERIFIED';recorded_at=$RecordedAt
    predecessor=[pscustomobject][ordered]@{path=$policy.v3_path;kind=[string]$v3.kind;record_sha256=[string]$v3.record_sha256;immutable_historical_receipt=$true}
    progression_package_presentation=[pscustomobject][ordered]@{path=$policy.presentation_path;kind=[string]$v5.kind;record_sha256=[string]$v5.record_sha256}
    current=[pscustomobject][ordered]@{package_source_sha256=[string]$v5.package_source.fingerprint_sha256;package_authority=[pscustomobject][ordered]@{path='targets/package-authority.json';kind=[string]$authority.kind;record_sha256=[string]$authority.record_sha256};tooling_inventory_predecessor_sha256=[string]$policy.v3_tooling_inventory_sha256;tooling_inventory=$toolingInventory;f210_f200_exact_engine_qualification_required=$true;f110_f100_progression_capability_nonclaim=$true}
    evolved_bindings=@($evolvedBindings)
    invariants=[pscustomobject][ordered]@{historical_mir41_lineage_immutable=$true;v3_progression_successor_immutable=$true;v5_package_presentation_immutable=$true;proof_input_authorities_typed_and_fail_closed=$true;f210_f200_exact_engine_qualification_required=$true;f110_f100_progression_capability_omitted_nonclaim=$true;current_mir41_release_operations_authorized=$false}
    transition_gate=[pscustomobject][ordered]@{development_merge=$true;private_build=$false;qualification=$false;technical_seal=$false;main_promotion=$false;version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
    record_sha256=''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  if (-not ((ConvertTo-MIR4BootstrapCanonicalJson -Value $record) | Test-Json -SchemaFile (Join-Path $repo $policy.output_schema))) { throw '[mir4-m41-m42-succession-v4-schema]' }
  return $record
}

function Get-MIR4M41ToM42ComposableSourceSuccessionV4 {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4M41ToM42ComposableSourceSuccessionV4Policy
  $expectedRecordSha256 = Get-MIR4M41ToM42ComposableSourceSuccessionV4ExpectedRecordSha256 -RepoRoot $repo
  # Read the immutable predecessor through its exact reader. A predecessor
  # hash copied into V4 is not evidence that the V3 record still exists and
  # retains its governed identity.
  $v3 = Get-MIR4M41ToM42ComposableSourceSuccessionV3 -RepoRoot $repo
  $raw = Get-Content -Raw -LiteralPath (Join-Path $repo $policy.output_path)
  $record = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not ((ConvertTo-MIR4BootstrapCanonicalJson -Value $record) | Test-Json -SchemaFile (Join-Path $repo $policy.output_schema)) -or -not (Test-MIR4BootstrapRecordHash -Record $record) -or $raw -cne ((ConvertTo-MIR4BootstrapCanonicalJson -Value $record) + [char]10)) { throw '[mir4-m41-m42-succession-v4-integrity]' }
  # V4 is an append-only control-plane receipt. A later package-presentation
  # successor may legitimately change player bytes, so V4 validates its own
  # immutable V3/V5 facts rather than regenerating against mutable checkout
  # state. The later successor must bind this exact receipt.
  if ([string]$record.kind -cne 'MIR4M41ToM42ComposableSourceSuccessionV4' -or
      [string]$record.status -cne 'MIR41-HISTORICAL-LINEAGE-PRESERVED-MIR42-PROOF-INPUT-CONTROL-PLANE-SUCCESSOR-STATIC-VERIFIED' -or
      [string]$record.record_sha256 -cne $expectedRecordSha256 -or
      [string]$record.predecessor.path -cne $policy.v3_path -or
      [string]$record.predecessor.kind -cne 'MIR4M41ToM42ComposableSourceSuccessionV3' -or
      [string]$record.predecessor.record_sha256 -cne [string]$v3.record_sha256 -or
      -not [bool]$record.predecessor.immutable_historical_receipt -or
      [string]$record.progression_package_presentation.path -cne $policy.presentation_path -or
      [string]$record.progression_package_presentation.kind -cne 'MIR4CurrentPackagePresentationV5' -or
      [string]$record.progression_package_presentation.record_sha256 -cne 'D2C73297B4A7BA404B13EEC0AB29C5CDE56357F04ED4B48C9B1099F2F2DA7470' -or
      [string]$record.current.package_source_sha256 -cne 'A476DDAFA5AB62BD6AEC69054E1A162C570DDB946520AF9234FC8FE0D79BEC2F' -or
      [string]$record.current.tooling_inventory_predecessor_sha256 -cne $policy.v3_tooling_inventory_sha256) {
    throw '[mir4-m41-m42-succession-v4-historical-integrity]'
  }
  Assert-MIR4M41ToM42ComposableSourceSuccessionV4CurrentBindings -RepoRoot $repo -Record $record | Out-Null
  Assert-MIR4M41ToM42SourceSuccessionGate -Gate $record.transition_gate -Code 'mir4-m41-m42-succession-v4-gate'
  return $record
}

function Test-MIR4M41ToM42ComposableSourceSuccessionV4 {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$RepoRoot,[object]$SuccessionRecord)
  if ($null -eq $SuccessionRecord) { $SuccessionRecord = Get-MIR4M41ToM42ComposableSourceSuccessionV4 -RepoRoot $RepoRoot }
  $expectedRecordSha256 = Get-MIR4M41ToM42ComposableSourceSuccessionV4ExpectedRecordSha256 -RepoRoot $RepoRoot
  if (-not (Test-MIR4BootstrapRecordHash -Record $SuccessionRecord) -or
      [string]$SuccessionRecord.record_sha256 -cne $expectedRecordSha256 -or
      [string]$SuccessionRecord.predecessor.record_sha256 -cne '387ECBA18CB90C6F92D6C4D8FA76EF54E85FB21278F93EFD455A55CA7998FA53' -or
      [string]$SuccessionRecord.current.package_source_sha256 -cne 'A476DDAFA5AB62BD6AEC69054E1A162C570DDB946520AF9234FC8FE0D79BEC2F') {
    throw '[mir4-m41-m42-succession-v4-historical-integrity]'
  }
  Assert-MIR4M41ToM42ComposableSourceSuccessionV4CurrentBindings -RepoRoot $RepoRoot -Record $SuccessionRecord | Out-Null
  Assert-MIR4M41ToM42SourceSuccessionGate -Gate $SuccessionRecord.transition_gate -Code 'mir4-m41-m42-succession-v4-gate'
  return [pscustomobject][ordered]@{status='passed-historical-mir41-to-current-mir42-proof-input-control-plane-succession';current_release_operations_authorized=$false;factorio_one_exact_engine_proof_required=$true;current_package_source_sha256=[string]$SuccessionRecord.current.package_source_sha256;record_sha256=[string]$SuccessionRecord.record_sha256}
}

# The existing public function is deliberately routed through the newest
# append-only successor. Consumers needing older facts use explicit readers.
function Test-MIR4M41ToM42ComposableSourceSuccession {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[object]$SuccessionRecord)
  return Test-MIR4M41ToM42ComposableSourceSuccessionV4 -RepoRoot $RepoRoot -SuccessionRecord $SuccessionRecord
}
