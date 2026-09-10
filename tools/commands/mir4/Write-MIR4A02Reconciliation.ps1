# MIR4-CANONICAL-EXECUTABLE-TEST
<#
  A02 is an evidence-producing reconciliation, not an admission writer.  The
  two commits below are the immutable R02/R03 observations cited by the
  adopted programme.  In particular, this command must never turn a preview,
  shadow, bootstrap, or historical component into player authority.
#>
[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputPath = 'spec/programmes/evidence/synthesis-2026-09-10/a02-component-reconciliation.json',
  [string]$ProofPath = 'spec/programmes/evidence/synthesis-2026-09-10/a02-current-source-materializer-proof.json',
  [switch]$Check,
  [switch]$UseExistingProof,
  [switch]$ReplaceExistingRecord,
  [switch]$TestOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')

$stableCommit = 'f458598732e9583a9d086032ebfbe9ffb747d130'
$retainedCommit = '3683369ba00cfbdd7f8872a5a1b24f0d59f31062'
$mergeBase = '3562377b520cccb071b97b3968946eae7024c950'
$canonicalOutput = 'spec/programmes/evidence/synthesis-2026-09-10/a02-component-reconciliation.json'
$canonicalProof = 'spec/programmes/evidence/synthesis-2026-09-10/a02-current-source-materializer-proof.json'

function Stop-A02 {
  param([bool]$Condition, [string]$Code)
  if (-not $Condition) { throw "[$Code]" }
}

function Invoke-A02Git {
  param([Parameter(Mandatory)][string[]]$Arguments)
  $result = @(& git -C $repo @Arguments)
  if ($LASTEXITCODE -ne 0) { throw "[mir4-a02-git] $($Arguments -join ' ')" }
  return $result
}

function Assert-A02PortablePath {
  param([Parameter(Mandatory)][string]$Path)
  Stop-A02 (-not [IO.Path]::IsPathRooted($Path) -and $Path -match '^[A-Za-z0-9._/-]+$' -and $Path -notmatch '(^|/)\.\.(/|$)') 'mir4-a02-path-shape'
}

function Get-A02Blob {
  param([Parameter(Mandatory)][string]$Commit, [Parameter(Mandatory)][string]$Path)
  Assert-A02PortablePath -Path $Path
  $object = "$Commit`:$Path"
  # A <commit>:<path> expression already resolves to its blob. Appending
  # ^{blob} makes Git treat the suffix as part of the path on this form.
  $blob = [string](@(Invoke-A02Git -Arguments @('rev-parse', $object))[0])
  Stop-A02 ($blob -match '^[0-9a-f]{40}$') 'mir4-a02-owned-blob'
  return $blob
}

function Get-A02RetainedDelta {
  $rows = @{}
  foreach ($line in @(Invoke-A02Git -Arguments @('diff', '--name-status', "$mergeBase...$retainedCommit"))) {
    $columns = @([string]$line -split "`t")
    if ($columns.Count -lt 2) { throw '[mir4-a02-delta-shape]' }
    $status = [string]$columns[0]
    $paths = if ($status -match '^[RC]') { @($columns | Select-Object -Skip 1) } else { @($columns[1]) }
    foreach ($path in $paths) {
      Assert-A02PortablePath -Path ([string]$path)
      $rows[[string]$path] = $status
    }
  }
  return $rows
}

# This catalogue deliberately names a small, bounded owning set for every R07
# component. It is not an inferred string search: the platform architecture
# identifies the owner domains, while every selected path must resolve to an
# immutable blob in both R02 and R03. Adding a component requires extending
# this table and its explicit destination rather than inheriting a blanket
# disposition.
function Get-A02ComponentOwners {
  return @(
    [pscustomobject]@{ id='source-distribution-codec'; paths=@('tools/mir/application/package/TargetMaterializer.ps1','tools/mir/cli/Invoke-MIR4PackageSource.ps1'); trace='package-excluded-governs-source-overlay-zip' },
    [pscustomobject]@{ id='target-identity-predecessor-contracts'; paths=@('targets/registry.json','targets/support-policy.json'); trace='package-excluded-governs-source-overlay-zip' },
    [pscustomobject]@{ id='legacy-compiler-host-adapter-v1'; paths=@('tools/mir/application/compiler/CompilationRun.ps1','tools/lib/mir4/CompilationRun.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='target-materializer'; paths=@('tools/mir/application/package/TargetMaterializer.ps1','targets/package-authority.json'); trace='package-excluded-governs-source-overlay-zip' },
    [pscustomobject]@{ id='package-surface-lock'; paths=@('src/mod/package-source.json','targets/package-authority.json'); trace='package-excluded-governs-source-overlay-zip' },
    [pscustomobject]@{ id='release-dag'; paths=@('tools/mir/application/release/ReleaseDag.ps1','spec/platform/mir4-preview-v0/release-dag.json'); trace='package-excluded' },
    [pscustomobject]@{ id='whole-platform-programme-v1'; paths=@('.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json','tools/mir/application/platform/WholePlatform.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='uppercase-f-target-presentation-v1'; paths=@('tools/mir/domain/targets/TargetKey.ps1','tools/lib/mir4/TargetKey.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='technology-acceptance-queue-v1'; paths=@('tools/mir/application/technology/TechnologyAcceptance.ps1','spec/schemas/mir4-technology-acceptance-queue-v1.schema.json'); trace='package-excluded' },
    [pscustomobject]@{ id='api-sdk-v0'; paths=@('spec/api/mir4-v0/contracts.json','sdk/preview/mir4/api-v0/powershell/MIR4.Api.V0.psm1'); trace='package-excluded' },
    [pscustomobject]@{ id='mep-v0'; paths=@('sdk/preview/mir4/lua/mir4_mep_v0.lua','tools/lib/mir4/MepDiscovery.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='query-profile-observation-v0'; paths=@('sdk/preview/mir4/reference/query-snapshot-f210.json','spec/schemas/experimental/mir4querysnapshotv0.schema.json'); trace='package-excluded' },
    [pscustomobject]@{ id='inspector-v0'; paths=@('sdk/preview/mir4/inspector/Export-MIR4SupportSnapshot.ps1','tools/mir/application/inspection/Inspector.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='target-provider-abi-v1'; paths=@('.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json','tools/mir/application/targets/TargetCompiler.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='normalized-compiler-v1'; paths=@('tools/mir/application/compiler/NormalizedCompiler.ps1','tools/lib/mir4/NormalizedCompiler.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='feature-setting-aggregate-v1'; paths=@('sdk/preview/mir4/reference/feature-setting-cutover-matrix.json','tools/mir/application/compiler/CompilationRun.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='provider-micro-protocol-v1'; paths=@('sdk/preview/mir4/reference/provider-micro-protocol-matrix.json','tools/mir/application/extensions/ModuleEcosystem.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='merge-law-catalogue-v1'; paths=@('sdk/preview/mir4/reference/merge-law-catalogue.json','tools/mir/application/compiler/CompilationRun.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='safety-kernel-policy-engine-boundary-v0'; paths=@('tools/mir/domain/safety/SafetyKernel.ps1','tools/mir/domain/policy/PolicyEngine.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='runtime-state-model-v1'; paths=@('tools/mir/application/runtime/RuntimeStateModel.ps1','tools/lib/mir4/RuntimeStateModel.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='runtime-registration-plan-v1'; paths=@('.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json','sdk/preview/mir4/reference/runtime-state-inventory.json'); trace='package-excluded' },
    [pscustomobject]@{ id='migration-graph-v1'; paths=@('sdk/preview/mir4/reference/migration-graph-matrix.json','spec/schemas/mir4-migration-graph-matrix-v1.schema.json'); trace='package-excluded' },
    [pscustomobject]@{ id='continuity-bundle-v1'; paths=@('sdk/preview/mir4/reference/continuity-bundle-template.json','tools/mir/application/custody/OfflineCandidateCustody.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='mep-v1'; paths=@('sdk/preview/mir4/mep-v1/package-metadata.json','tools/mir/application/extensions/MepDiscovery.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='extension-closure-v1'; paths=@('sdk/preview/mir4/reference/extension-closure-v1.json','tools/mir/application/extensions/ModuleEcosystem.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='api-sdk-v1'; paths=@('sdk/preview/mir4/api-v1/package-metadata.json','tools/mir/application/extensions/SdkV1.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='synthetic-reference-consumer-v1'; paths=@('sdk/preview/mir4/reference-extension-v1/extension.json','fixtures/mir4-mep-v1/positive/reference-extension.json'); trace='package-excluded' },
    [pscustomobject]@{ id='process-ir-v1'; paths=@('tools/mir/application/processir/ProcessIR.ps1','sdk/preview/mir4/reference/process-ir-inventory.json'); trace='package-excluded' },
    [pscustomobject]@{ id='effect-channel-registry-v1'; paths=@('sdk/preview/mir4/reference/effect-channel-registry-v1.json','spec/schemas/mir4-effect-channel-registry-v1.schema.json'); trace='package-excluded' },
    [pscustomobject]@{ id='autonomous-synthesis-v1'; paths=@('scripts/Invoke-MIRRuleSynthesis.ps1','.mir/rule-synthesis.json'); trace='package-excluded' },
    [pscustomobject]@{ id='compatibility-subject-ledger-v1'; paths=@('sdk/preview/mir4/reference/compatibility-subject-ledger-v1.json','tools/mir/application/inspection/SupportAssessment.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='compatibility-factory-v1'; paths=@('sdk/preview/mir4/reference/compatibility-factory-plan-v1.json','tools/mir/application/inspection/CompatibilityFactory.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='inspector-v1'; paths=@('sdk/preview/mir4/inspector-v1/Export-MIR4InspectionBundle.ps1','tools/mir/application/inspection/Inspector.ps1'); trace='package-excluded' },
    [pscustomobject]@{ id='historical-target-providers-v0'; paths=@('.mir/releases/waves/mir4-r0/MIR4-Historical-Succession-ProgrammeV1.json','tools/mir/application/history/HistoricalSuccession.ps1'); trace='package-excluded' }
  )
}

function Resolve-A02OutputPath {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$CanonicalPath)
  Assert-A02PortablePath -Path $Path
  $full = [IO.Path]::GetFullPath((Join-Path $repo $Path))
  $prefix = $repo.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  Stop-A02 ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) 'mir4-a02-output-boundary'
  if (-not $TestOutput) {
    $expected = [IO.Path]::GetFullPath((Join-Path $repo $CanonicalPath))
    Stop-A02 ($full.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) 'mir4-a02-output-authority'
  }
  return $full
}

function Read-A02Proof {
  param([Parameter(Mandatory)][string]$Path)
  Stop-A02 (Test-Path -LiteralPath $Path -PathType Leaf) 'mir4-a02-materializer-proof-missing'
  $raw = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
  Stop-A02 ($raw | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-current-source-materializer-proof-v1.schema.json')) 'mir4-a02-materializer-proof-schema'
  $proof = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  Stop-A02 (Test-MIR4BootstrapRecordHash -Record $proof) 'mir4-a02-materializer-proof-selfhash'
  Stop-A02 ([string]$proof.status -ceq 'passed-four-target-current-source-determinism') 'mir4-a02-materializer-proof-status'
  $targets = @($proof.targets)
  Stop-A02 ($targets.Count -eq 4 -and (@($targets.target | Sort-Object) -join '|') -ceq 'f100|f110|f200|f210') 'mir4-a02-materializer-proof-targets'
  foreach ($target in $targets) {
    Stop-A02 ([bool]$target.deterministic_archive_bytes -and [string]$target.archive_a -ceq [string]$target.archive_b -and [string]$target.content_sha256 -match '^[A-F0-9]{64}$') 'mir4-a02-materializer-proof-target'
  }
  return $proof
}

function New-A02Record {
  param([Parameter(Mandatory)]$Proof)
  Stop-A02 (([string](@(Invoke-A02Git -Arguments @('rev-parse', "$stableCommit`^{commit}"))[0])) -ceq $stableCommit) 'mir4-a02-stable-commit'
  Stop-A02 (([string](@(Invoke-A02Git -Arguments @('rev-parse', "$retainedCommit`^{commit}"))[0])) -ceq $retainedCommit) 'mir4-a02-retained-commit'
  Stop-A02 (([string](@(Invoke-A02Git -Arguments @('merge-base', $stableCommit, $retainedCommit))[0])) -ceq $mergeBase) 'mir4-a02-merge-base'

  $deliveryPath = 'spec/programmes/inputs/synthesis-2026-09-05/COMPONENT_DELIVERY.json'
  $platformPath = 'spec/platform/mir4-preview-v0/platform.json'
  $delivery = Get-Content -Raw -LiteralPath (Join-Path $repo $deliveryPath) | ConvertFrom-Json -Depth 100 -DateKind String
  $platform = Get-Content -Raw -LiteralPath (Join-Path $repo $platformPath) | ConvertFrom-Json -Depth 100 -DateKind String
  $expectedIds = @($delivery.components | ForEach-Object { [string]$_.id })
  Stop-A02 ($expectedIds.Count -eq 34 -and @($expectedIds | Sort-Object -Unique).Count -eq 34) 'mir4-a02-component-inventory'
  Stop-A02 ((@($platform.components | ForEach-Object { [string]$_.id } | Sort-Object) -join '|') -ceq (@($expectedIds | Sort-Object) -join '|')) 'mir4-a02-platform-coverage'

  $owners = @(Get-A02ComponentOwners)
  Stop-A02 ($owners.Count -eq 34 -and @($owners.id | Sort-Object -Unique).Count -eq 34 -and ((@($owners.id | Sort-Object) -join '|') -ceq (@($expectedIds | Sort-Object) -join '|'))) 'mir4-a02-owner-catalogue'
  $ownerById = @{}
  foreach ($owner in $owners) { $ownerById[[string]$owner.id] = $owner }
  $delta = Get-A02RetainedDelta
  $manifest = Get-Content -Raw -LiteralPath (Join-Path $repo 'src/mod/package-source.json') | ConvertFrom-Json -Depth 100 -DateKind String
  $sourcePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($binding in @($manifest.bindings)) { [void]$sourcePaths.Add([string]$binding.source_path) }
  $overlays = @('targets/f210/overlay.json','targets/f200/overlay.json','targets/f110/overlay.json','targets/f100/overlay.json')
  $targetZipRows = @($Proof.targets | Sort-Object target | ForEach-Object { [ordered]@{target=[string]$_.target;archive_sha256=[string]$_.archive_a;content_sha256=[string]$_.content_sha256;entry_count=[int]$_.entry_count;composition_record_sha256=[string]$_.composition_record_a} })

  $rows = [Collections.Generic.List[object]]::new()
  foreach ($component in @($delivery.components)) {
    $id = [string]$component.id
    $owner = $ownerById[$id]
    Stop-A02 ($null -ne $owner) 'mir4-a02-unknown-component'
    $platformRow = @($platform.components | Where-Object { [string]$_.id -ceq $id })
    Stop-A02 ($platformRow.Count -eq 1) 'mir4-a02-platform-row'
    $ownedPaths = [Collections.Generic.List[object]]::new()
    foreach ($path in @($owner.paths | Sort-Object -Unique)) {
      $stableBlob = Get-A02Blob -Commit $stableCommit -Path $path
      $retainedBlob = Get-A02Blob -Commit $retainedCommit -Path $path
      $deltaStatus = if ($delta.ContainsKey($path)) { [string]$delta[$path] } else { 'unchanged' }
      $ownedPaths.Add([ordered]@{
        path = $path
        stable_blob = $stableBlob
        retained_blob = $retainedBlob
        retained_delta = $deltaStatus
      })
    }
    Stop-A02 ($ownedPaths.Count -gt 0) 'mir4-a02-unbound-component'
    # A02 deliberately closes only an exactly unchanged branch fact.  A
    # changed blob or R14 delta needs its own characterized review; this
    # bounded reconciliation must not manufacture that characterization.
    $changedPaths = @($ownedPaths | Where-Object { [string]$_.stable_blob -cne [string]$_.retained_blob -or [string]$_.retained_delta -cne 'unchanged' })
    Stop-A02 ($changedPaths.Count -eq 0) 'mir4-a02-uncharacterized-cross-branch-delta'
    foreach ($pathRow in $ownedPaths) { Stop-A02 (-not $sourcePaths.Contains([string]$pathRow.path)) 'mir4-a02-package-exclusion' }
    $excludedOwnedPaths = @($ownedPaths | ForEach-Object { [string]$_.path })
    $trace = if ([string]$owner.trace -ceq 'package-excluded-governs-source-overlay-zip') {
      [ordered]@{
        mode = 'package-excluded-governs-source-overlay-zip'
        exclusion_evidence = @('src/mod/package-source.json','targets/package-authority.json','spec/platform/mir4-preview-v0/platform.json')
        excluded_owned_paths = $excludedOwnedPaths
        source_manifest = 'src/mod/package-source.json'
        target_overlays = $overlays
        materializer_proof = $canonicalProof
        target_archives = $targetZipRows
        player_authority = $false
      }
    } else {
      [ordered]@{
        mode = 'package-excluded'
        exclusion_evidence = @('src/mod/package-source.json','targets/package-authority.json','spec/platform/mir4-preview-v0/platform.json')
        excluded_owned_paths = $excludedOwnedPaths
        player_authority = $false
      }
    }
    $rows.Add([ordered]@{
      id = $id
      reported_maturity = [string]$component.reported_maturity
      platform_mode = [string]$platformRow[0].mode
      destination = [string]$component.destination
      next_obligation = [string]$component.next_obligation
      canonical_owned_paths = @($ownedPaths)
      package_trace = $trace
      cross_branch_delta = [ordered]@{
        status = 'unchanged'
        compared_owned_path_count = $ownedPaths.Count
        changed_owned_path_count = 0
      }
      semantic_disposition = 'unchanged'
      semantic_evidence = [ordered]@{
        source = 'R14'
        comparison = "$mergeBase...$retainedCommit"
        stable_comparison_ref = $stableCommit
        retained_comparison_ref = $retainedCommit
      }
      assessment = [ordered]@{
        assessed = $true
        complete = $true
        unresolved = $false
        closure = 'A02 records ownership, destination, immutable branch facts and non-interference only; component graduation requires its own admitted consumer and proof.'
      }
      admitted_by_this_review = $false
      graduated = $false
      player_authority = $false
    })
  }
  Stop-A02 ($rows.Count -eq 34 -and @($rows.id | Sort-Object -Unique).Count -eq 34) 'mir4-a02-row-cardinality'
  Stop-A02 (@($rows | Where-Object { -not $_.assessment.assessed -or -not $_.assessment.complete -or $_.assessment.unresolved -or $_.admitted_by_this_review -or $_.graduated -or $_.player_authority }).Count -eq 0) 'mir4-a02-completion-controls'

  $record = [ordered]@{
    schema = 1
    kind = 'MIR4A02ComponentReconciliationV1'
    task = 'A02'
    status = 'complete'
    reconciliation_subject = [ordered]@{
      stable_commit = $stableCommit
      retained_dev_commit = $retainedCommit
      merge_base = $mergeBase
      comparison_mode = 'merge-base-to-retained-dev-with-stable-reference'
    }
    sources = @('R02','R03','R14')
    component_inventory = [ordered]@{
      path = $deliveryPath
      component_count = 34
      ids = @($expectedIds)
    }
    current_authority = [ordered]@{
      package_authority_sha256 = [string]$Proof.package_authority_sha256
      package_source_sha256 = [string]$Proof.package_source_sha256
      source_manifest_sha256 = [string]$Proof.source_manifest_sha256
      materializer_abi = [string]$Proof.materializer_abi
      package_cutover = [bool]$Proof.transition_gate.package_cutover
      release_authority = $false
      player_mutation_authority = $false
      component_graduation_authority = $false
    }
    materializer_proof = [ordered]@{
      path = $canonicalProof
      record_sha256 = [string]$Proof.record_sha256
      status = [string]$Proof.status
      targets = $targetZipRows
    }
    components = @($rows)
    authorities = [ordered]@{
      all_components_assessed = $true
      blanket_graduation = $false
      player_mutation_authorized = $false
      prototype_write_authorized = $false
      setting_mutation_authorized = $false
      persistent_state_mutation_authorized = $false
      migration_authorized = $false
      public_support_claim_authorized = $false
      release_authority = $false
      publication_authorized = $false
    }
    record_sha256 = ''
  }
  # Bootstrap self-hashing enumerates PSObject properties. Promote this
  # ordered construction dictionary before hashing so the persisted record and
  # a subsequently deserialized record have the identical unsigned shape.
  $record = [pscustomobject]$record
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

$outputFull = Resolve-A02OutputPath -Path $OutputPath -CanonicalPath $canonicalOutput
$proofFull = Resolve-A02OutputPath -Path $ProofPath -CanonicalPath $canonicalProof
if ($Check) {
  $proof = Read-A02Proof -Path $proofFull
  $record = New-A02Record -Proof $proof
  Stop-A02 (Test-Path -LiteralPath $outputFull -PathType Leaf) 'mir4-a02-record-missing'
  $raw = [IO.File]::ReadAllText($outputFull).Replace("`r`n", "`n")
  Stop-A02 ($raw | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-a02-component-reconciliation-v1.schema.json')) 'mir4-a02-record-schema'
  $stored = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  Stop-A02 (Test-MIR4BootstrapRecordHash -Record $stored) 'mir4-a02-record-selfhash'
  $expected = ConvertTo-MIR4BootstrapCanonicalJson -Value $record
  Stop-A02 ($raw.TrimEnd("`n") -ceq $expected) 'mir4-a02-record-stale'
  return $record
}

$proofParent = Split-Path -Parent $proofFull
if (-not (Test-Path -LiteralPath $proofParent -PathType Container)) { New-Item -ItemType Directory -Force -Path $proofParent | Out-Null }
# Materialization is deliberately performed only in explicit write mode. The
# recovery path is equally explicit: it can bind a previously completed proof
# but never refreshes it. This avoids a restarted turn silently changing the
# four-target evidence it is meant to reconcile.
$proof = if ($UseExistingProof) {
  Read-A02Proof -Path $proofFull
} else {
  Invoke-MIR4CurrentSourceMaterializerProof -RepoRoot $repo -OutputRoot (Join-Path $repo 'build/a02-materializer') -ReportPath $proofFull
}
$record = New-A02Record -Proof $proof
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('mir4-a02-' + [guid]::NewGuid().ToString('N') + '.json')
try {
  [void](Write-MIR4BootstrapRecord -Record $record -Path $scratch)
  $projection = [IO.File]::ReadAllText($scratch)
  Stop-A02 ($projection | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-a02-component-reconciliation-v1.schema.json')) 'mir4-a02-record-schema'
  if (Test-Path -LiteralPath $outputFull) {
    if ([IO.File]::ReadAllText($outputFull) -ceq $projection) {
      # The canonical evidence is already the deterministic projection.
    } elseif ($ReplaceExistingRecord) {
      Stop-A02 $UseExistingProof 'mir4-a02-replace-requires-existing-proof'
      $tracked = @(& git -C $repo ls-files --error-unmatch -- $canonicalOutput 2>$null)
      $trackedExit = $LASTEXITCODE
      Stop-A02 ($trackedExit -ne 0 -and $tracked.Count -eq 0) 'mir4-a02-replace-tracked-record'
      $existing = [IO.File]::ReadAllText($outputFull) | ConvertFrom-Json -Depth 100 -DateKind String
      Stop-A02 ([string]$existing.kind -ceq 'MIR4A02ComponentReconciliationV1' -and [string]$existing.task -ceq 'A02' -and (Test-MIR4BootstrapRecordHash -Record $existing)) 'mir4-a02-replace-existing-record'
      Stop-A02 ([string]$existing.materializer_proof.record_sha256 -ceq [string]$proof.record_sha256) 'mir4-a02-replace-proof-binding'
      # File.Replace needs a concrete backup path on this Windows runtime.
      # Preserve the superseded, untracked draft outside evidence authority so
      # a one-time truthfulness correction is recoverable and cannot erase a
      # later accepted projection.
      $backup = Join-Path $repo 'build/a02-rejected/a02-component-reconciliation.pre-truthfulness-correction.json'
      Stop-A02 (-not (Test-Path -LiteralPath $backup)) 'mir4-a02-replace-backup-exists'
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
      [IO.File]::Replace($scratch, $outputFull, $backup)
      $scratch = $null
    } else {
      Stop-A02 $false 'mir4-a02-immutable-overwrite'
    }
  } else {
    $parent = Split-Path -Parent $outputFull
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::Move($scratch, $outputFull, $false)
    $scratch = $null
  }
  return $record
} finally {
  if ($null -ne $scratch -and (Test-Path -LiteralPath $scratch)) { Remove-Item -LiteralPath $scratch -Force }
}
