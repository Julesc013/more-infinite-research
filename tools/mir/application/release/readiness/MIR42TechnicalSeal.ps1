Set-StrictMode -Version Latest

$mir42SealRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Assert-MIR4NoReparseAncestors -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Get-MIR4CanonicalPackageSourceFingerprint -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/mir/application/package/PackageAuthority.ps1')
}
if (-not (Get-Command Test-MIR4OpenSshSignatureV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/mir/application/custody/OfflineCandidateCustody.ps1')
}
if (-not (Get-Command Assert-MIR42FourTargetPackageExcludedSurface -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1')
}
if (-not (Get-Command Test-MIR4FixedFactorioEngineIdentity -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/lib/validation/FactorioVersionPolicy.ps1')
}
if (-not (Get-Command Get-MIR4F210CurrentEngineCapHarnessAdmissionV3 -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/mir/application/release/F210QualificationPolicy.ps1')
}
if (-not (Get-Command Assert-MIR430ClassicStartupStressObservation -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/mir/application/release/readiness/MIR42EvidenceReconciliation.ps1')
}

$script:MIR42SealTargets = @('f210', 'f200', 'f110', 'f100')
$script:MIR42SealNineTargetCandidates = @('f210', 'f200', 'f110', 'f100', 'f017', 'f016', 'f015', 'f014', 'f013')
$script:MIR42SealHistoricalTargets = @('f017', 'f016', 'f015', 'f014', 'f013')
$script:MIR42SealReleaseAcceptanceCriteria = @(
  'fresh-exact-loads', 'settings-profile-continuity', 'research-progression', 'migrations-two-reload',
  'compatibility-canaries', 'target-omissions', 'performance-telemetry', 'package-exclusion',
  'deterministic-reconstruction'
)
$script:MIR42SealVerifierDependencyPaths = @(
  'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1',
  'tools/mir/application/release/readiness/MIR42EvidenceReconciliation.ps1',
  'governance/repository/mir430-emergency-performance-v1.json',
  'spec/schemas/mir430-emergency-performance-v1.schema.json',
  'spec/schemas/mir430-named-startup-stress-profile-v1.schema.json',
  'spec/schemas/mir430-classic-startup-stress-observation-v1.schema.json',
  'fixtures/run-profiles/mir430-startup-galore-space-age-f200.json',
  'fixtures/run-profiles/mir430-startup-bob-angel-f200.json',
  'fixtures/run-profiles/mir430-startup-omni-bob-angel-46-f200.json',
  'fixtures/assert-mir430-startup-work/info.json',
  'fixtures/assert-mir430-startup-work/settings-updates.lua',
  'fixtures/assert-mir430-startup-work/data-final-fixes.lua',
  'tools/mir/application/release/readiness/MIR42ProtectedMainPromotion.ps1',
  'spec/schemas/mir42-nine-target-release-cut-programme-v1.schema.json',
  'tools/commands/release/Invoke-MIR42FourTargetSealPromotion.ps1',
  'tools/lib/mir4/BootstrapMaterialization.ps1',
  'tools/mir/application/package/PackageAuthority.ps1',
  'tools/mir/application/custody/OfflineCandidateCustody.ps1',
  'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1',
  'tools/lib/validation/FactorioVersionPolicy.ps1',
  'tools/mir/application/release/F210QualificationPolicy.ps1'
)

function Read-MIR42SealRecord {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "[$Code-missing] $Path" }
  try { $record = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100 -DateKind String }
  catch { throw "[$Code-json] $Path" }
  if ($null -eq $record) { throw "[$Code-empty] $Path" }
  if ($record.PSObject.Properties.Name -notcontains 'record_sha256' -or
      [string]$record.record_sha256 -notmatch '^[A-F0-9]{64}$' -or
      -not (Test-MIR4BootstrapRecordHash -Record $record)) { throw "[$Code-record-hash] $Path" }
  return [pscustomobject][ordered]@{
    path = (Resolve-Path -LiteralPath $Path).Path
    sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    record = $record
  }
}

function Assert-MIR42SealSource {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Source,[Parameter(Mandatory)][string]$Code)
  foreach ($field in @('commit','tree','package_source_sha256')) {
    if ($Source.PSObject.Properties.Name -notcontains $field -or [string]::IsNullOrWhiteSpace([string]$Source.$field)) {
      throw "[$Code-source-field] $field"
    }
  }
  $dirty = @(& git -C $RepoRoot status --porcelain=v1 --untracked-files=all)
  if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw "[$Code-source-dirty]" }
  $commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
  $tree = (& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
  if ($LASTEXITCODE -ne 0 -or $commit -cne [string]$Source.commit -or $tree -cne [string]$Source.tree) {
    throw "[$Code-source-tree-drift]"
  }
  $packageSource = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot
  if ($packageSource -cne [string]$Source.package_source_sha256) { throw "[$Code-package-source-drift]" }
  return [pscustomobject][ordered]@{commit=$commit;tree=$tree;package_source_sha256=$packageSource}
}

function Assert-MIR42SealExternalPathSeparatedFromRepository {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  $full = [IO.Path]::GetFullPath($Path)
  $repo = [IO.Path]::GetFullPath($RepoRoot)
  $fullBoundary = if ($full.EndsWith([string][IO.Path]::DirectorySeparatorChar) -or $full.EndsWith([string][IO.Path]::AltDirectorySeparatorChar)) { $full } else { $full + [IO.Path]::DirectorySeparatorChar }
  $repoBoundary = if ($repo.EndsWith([string][IO.Path]::DirectorySeparatorChar) -or $repo.EndsWith([string][IO.Path]::AltDirectorySeparatorChar)) { $repo } else { $repo + [IO.Path]::DirectorySeparatorChar }
  if ($full -ceq $repo -or $full.StartsWith($repoBoundary,[StringComparison]::OrdinalIgnoreCase) -or $repo.StartsWith($fullBoundary,[StringComparison]::OrdinalIgnoreCase)) {
    throw "[$Code-repository]"
  }
}

function Assert-MIR42SealTargetSet {
  param([Parameter(Mandatory)]$Rows,[Parameter(Mandatory)][string]$Code,
    [ValidateSet('four-target','nine-target')][string]$Scope='four-target')
  $actual = @($Rows | ForEach-Object { [string]$_.target })
  $expected = if ($Scope -ceq 'nine-target') { @($script:MIR42SealNineTargetCandidates) } else { @($script:MIR42SealTargets) }
  if ($actual.Count -ne $expected.Count -or ($actual -join '|') -cne ($expected -join '|')) {
    throw "[$Code-target-set]"
  }
}

function Get-MIR42SealCandidateTargetScope {
  param([Parameter(Mandatory)]$Rows,[Parameter(Mandatory)][string]$Code)
  $actual = @($Rows | ForEach-Object { [string]$_.target })
  if (($actual -join '|') -ceq ($script:MIR42SealTargets -join '|')) { return 'four-target' }
  if (($actual -join '|') -ceq ($script:MIR42SealNineTargetCandidates -join '|')) { return 'nine-target' }
  throw "[$Code-target-set]"
}

function Get-MIR42SealCandidateScope {
  param([Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][string]$Code)
  $derived = Get-MIR42SealCandidateTargetScope -Rows @($Candidate.targets) -Code $Code
  if ($Candidate.PSObject.Properties.Name -contains 'scope' -and -not [string]::IsNullOrWhiteSpace([string]$Candidate.scope) -and [string]$Candidate.scope -cne $derived) {
    throw "[$Code-scope]"
  }
  return $derived
}

function Get-MIR42SealScopeContract {
  param([Parameter(Mandatory)][ValidateSet('four-target','nine-target')][string]$Scope)
  if ($Scope -ceq 'four-target') {
    return [pscustomobject][ordered]@{
      evidence_kind = 'MIR42FourTargetEvidenceReconciliationV1'
      evidence_status = 'MIR-4.2-FOUR-TARGET-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED'
      reconciliation_target_requirement = 'all_four_targets_required'
      engine_run_kind = 'MIR42FourTargetEngineRunV1'
      engine_run_status = 'four-target-base-default-real-engine-probes-passed-private-unqualified'
      binder_kind = 'MIR42FourTargetRealEngineEvidenceBinderV1'
      binder_status = 'MIR-4.2-FOUR-TARGET-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED'
      campaign_kind = 'MIR42FourTargetRealEngineCandidateCampaignV1'
      campaign_status = 'MIR-4.2-FOUR-TARGET-REAL-ENGINE-CAMPAIGN-PASSED-PRIVATE-UNSEALED'
      independent_kind = 'MIR42FourTargetIndependentEvidenceRehashV1'
      independent_status = 'MIR-4.2-FOUR-TARGET-INDEPENDENT-EVIDENCE-REHASH-PASSED-PRIVATE-UNQUALIFIED'
      independent_target_requirement = 'all_four_targets_required'
      programme_path = '.mir/releases/governance/mir4/MIR42-Release-Cut-ProgrammeV1.json'
      programme_kind = 'MIR42ReleaseCutProgrammeV1'
      trust_root_kind = 'MIR42ExternalT16LedgerTrustRootV1'
      readiness_kind = 'MIR42FourTargetTechnicalSealReadinessV1'
      readiness_status_prefix = 'MIR-4.2-FOUR-TARGET-TECHNICAL-SEAL-'
      seal_kind = 'MIR42FourTargetTechnicalSealV1'
      seal_status = 'MIR-4.2-FOUR-TARGET-TECHNICALLY-SEALED-AWAITING-PROTECTED-MAIN-PR'
      restore_kind = 'MIR42FourTargetGovernedOfflineRestoreDrillV1'
      restore_status = 'MIR-4.2-FOUR-TARGET-GOVERNED-OFFLINE-RESTORE-PASSED-POST-SEAL'
      restore_challenge_kind = 'MIR42FourTargetGovernedOfflineRestoreChallengeV1'
    }
  }
  return [pscustomobject][ordered]@{
    evidence_kind = 'MIR42NineTargetEvidenceReconciliationV1'
    evidence_status = 'MIR-4.2-NINE-TARGET-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED'
    reconciliation_target_requirement = 'all_nine_targets_required'
    engine_run_kind = 'MIR42NineTargetEngineRunV1'
    engine_run_status = 'nine-target-base-default-real-engine-probes-passed-private-unqualified'
    binder_kind = 'MIR42NineTargetRealEngineEvidenceBinderV1'
    binder_status = 'MIR-4.2-NINE-TARGET-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED'
    campaign_kind = 'MIR42NineTargetRealEngineCandidateCampaignV1'
    campaign_status = 'MIR-4.2-NINE-TARGET-REAL-ENGINE-CAMPAIGN-PASSED-PRIVATE-UNSEALED'
    independent_kind = 'MIR42NineTargetIndependentEvidenceRehashV1'
    independent_status = 'MIR-4.2-NINE-TARGET-INDEPENDENT-EVIDENCE-REHASH-PASSED-PRIVATE-UNQUALIFIED'
    independent_target_requirement = 'all_nine_targets_required'
    programme_path = '.mir/releases/governance/mir4/MIR42-Nine-Target-Release-Cut-ProgrammeV1.json'
    programme_kind = 'MIR42NineTargetReleaseCutProgrammeV1'
    trust_root_kind = 'MIR42NineTargetExternalT16LedgerTrustRootV1'
    readiness_kind = 'MIR42NineTargetTechnicalSealReadinessV1'
    readiness_status_prefix = 'MIR-4.2-NINE-TARGET-TECHNICAL-SEAL-'
    seal_kind = 'MIR42NineTargetTechnicalSealV1'
    seal_status = 'MIR-4.2-NINE-TARGET-TECHNICALLY-SEALED-AWAITING-PROTECTED-MAIN-PR'
    restore_kind = 'MIR42NineTargetGovernedOfflineRestoreDrillV1'
    restore_status = 'MIR-4.2-NINE-TARGET-GOVERNED-OFFLINE-RESTORE-PASSED-POST-SEAL'
    restore_challenge_kind = 'MIR42NineTargetGovernedOfflineRestoreChallengeV1'
  }
}

function Get-MIR42EngineEvidenceBindingContract {
  param([Parameter(Mandatory)]$Candidate,[switch]$PublishedMaintenance)
  $scope = Get-MIR42SealCandidateScope -Candidate $Candidate -Code 'mir42-engine-evidence-contract-candidate'
  $contract = Get-MIR42SealScopeContract -Scope $scope
  if ($PublishedMaintenance) {
    if ($scope -cne 'nine-target') { throw '[mir42-engine-evidence-maintenance-candidate-scope]' }
    $version = Get-MIR42SealCandidateConstructionVersionContract -RepoRoot $mir42SealRepoRoot -Manifest $Candidate.identity.record
    if ([string]$version.source_version -cnotin @('4.2.1','4.2.2','4.2.3','4.3.0','4.3.1')) { throw '[mir42-engine-evidence-maintenance-candidate-scope]' }
    $contract | Add-Member -NotePropertyName maintenance_source_version -NotePropertyValue ([string]$version.source_version)
    $contract.evidence_kind = 'MIR42NineTargetMaintenanceEvidenceReconciliationV1'
    $contract.evidence_status = "MIR-$($contract.maintenance_source_version)-NINE-TARGET-MAINTENANCE-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED"
    $contract.engine_run_kind = 'MIR42NineTargetMaintenanceEngineRunV1'
    $contract.engine_run_status = 'nine-target-maintenance-base-default-real-engine-probes-passed-private-unqualified'
    $contract.binder_kind = 'MIR42NineTargetMaintenanceRealEngineEvidenceBinderV1'
    $contract.binder_status = "MIR-$($contract.maintenance_source_version)-NINE-TARGET-MAINTENANCE-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED"
  }
  return $contract
}

function Get-MIR42IndividualEngineEvidenceBindingContract {
  param([Parameter(Mandatory)]$Candidate,[switch]$PublishedMaintenance)
  if (-not $PublishedMaintenance) { throw '[mir42-individual-engine-run-maintenance-required]' }
  $contract = Get-MIR42EngineEvidenceBindingContract -Candidate $Candidate -PublishedMaintenance
  if ([string]$contract.maintenance_source_version -cnotin @('4.2.3','4.3.0','4.3.1')) {
    throw '[mir42-individual-engine-run-source-version]'
  }
  $contract.engine_run_kind = 'MIR42NineTargetMaintenanceIndividualEngineRunV1'
  $contract.engine_run_status = 'nine-target-maintenance-individual-real-engine-probes-passed-private-unqualified'
  $contract.binder_kind = 'MIR42NineTargetMaintenanceIndividualRealEngineEvidenceBinderV1'
  $contract.binder_status = "MIR-$($contract.maintenance_source_version)-NINE-TARGET-MAINTENANCE-INDIVIDUAL-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED"
  return $contract
}

function Assert-MIR42EngineEvidenceMaintenanceCustody {
  param([Parameter(Mandatory)]$Recorded,[Parameter(Mandatory)]$Current,[Parameter(Mandatory)][string]$Code)
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $Recorded) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $Current)) {
    throw "[$Code]"
  }
}

function Get-MIR42JoinedCampaignInputContract {
  param([Parameter(Mandatory)]$Candidate,[switch]$PublishedMaintenance,[switch]$IndividualNativeInput)
  $contract = if ($IndividualNativeInput) {
    Get-MIR42IndividualEngineEvidenceBindingContract -Candidate $Candidate -PublishedMaintenance:$PublishedMaintenance
  } else {
    Get-MIR42EngineEvidenceBindingContract -Candidate $Candidate -PublishedMaintenance:$PublishedMaintenance
  }
  if ($PublishedMaintenance) {
    if ($IndividualNativeInput) {
      $contract.campaign_kind = 'MIR42NineTargetMaintenanceIndividualRealEngineCandidateCampaignV1'
      $contract.campaign_status = "MIR-$($contract.maintenance_source_version)-NINE-TARGET-MAINTENANCE-INDIVIDUAL-REAL-ENGINE-CAMPAIGN-PASSED-PRIVATE-UNSEALED"
    } else {
      $contract.campaign_kind = 'MIR42NineTargetMaintenanceRealEngineCandidateCampaignV1'
      $contract.campaign_status = "MIR-$($contract.maintenance_source_version)-NINE-TARGET-MAINTENANCE-REAL-ENGINE-CAMPAIGN-PASSED-PRIVATE-UNSEALED"
    }
  }
  return $contract
}

function Assert-MIR42MaintenanceCampaignCustody {
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)]$PublishedInputs)
  Assert-MIR42EngineEvidenceMaintenanceCustody -Recorded $Record.published_maintenance_predecessor -Current $PublishedInputs -Code 'mir42-maintenance-campaign-custody-binding'
  $expected = $script:MIR42SealNineTargetCandidates
  $actual = @($Record.targets | ForEach-Object { [string]$_.target })
  if ($actual.Count -ne $expected.Count -or ($actual -join '|') -cne ($expected -join '|')) {
    throw '[mir42-maintenance-campaign-target-set]'
  }
  foreach ($row in $Record.targets) {
    $inputs = @($PublishedInputs.targets | Where-Object { [string]$_.target -ceq [string]$row.target })
    if ($inputs.Count -ne 1) { throw '[mir42-maintenance-campaign-predecessor-cardinality]' }
    Assert-MIR42EngineEvidenceMaintenanceExecution -Target ([string]$row.target) -Execution $row.engine_execution -PublishedInput $inputs[0]
  }
}

function Assert-MIR42EngineEvidenceMaintenanceExecution {
  param([Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)]$Execution,[Parameter(Mandatory)]$PublishedInput)
  if ($Execution.PSObject.Properties.Name -notcontains 'published_maintenance_predecessor' -or
      [string]$PublishedInput.target -cne $Target -or
      -not ([string]$Execution.predecessor.path).Equals([string]$PublishedInput.path,[StringComparison]::OrdinalIgnoreCase) -or
      [string]$Execution.predecessor.sha256 -cne [string]$PublishedInput.sha256 -or
      [string]$Execution.predecessor.version -cne [string]$PublishedInput.version) {
    throw "[mir42-engine-evidence-maintenance-predecessor-binding] $Target"
  }
  Assert-MIR42EngineEvidenceMaintenanceCustody -Recorded $Execution.published_maintenance_predecessor -Current $PublishedInput -Code ('mir42-engine-evidence-maintenance-custody-binding-' + $Target)
}

function Assert-MIR42SealCandidateScopeMatch {
  param([Parameter(Mandatory)]$Rows,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][string]$Code)
  $actual = Get-MIR42SealCandidateTargetScope -Rows $Rows -Code $Code
  $expected = Get-MIR42SealCandidateScope -Candidate $Candidate -Code $Code
  if ($actual -cne $expected) { throw "[$Code-target-set]" }
}

function Resolve-MIR42SealContainedArtifactPath {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Code)
  if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath) -or
      $RelativePath.Replace('\','/') -match '(^|/)\.\.(/|$)') { throw "[$Code-path]" }
  $candidate = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
  try {
    $null = Assert-MIR4DescendantPath -Root $Root -Path $candidate
    $null = Assert-MIR4NoReparseAncestors -Root $Root -Path $candidate
  } catch { throw "[$Code-path]" }
  return $candidate
}

function Resolve-MIR42SealImmutableFile {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Sha256,[Parameter(Mandatory)][string]$Code)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path) -or $Sha256 -notmatch '^[A-F0-9]{64}$') { throw "[$Code-path]" }
  $full = [IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[$Code-missing]" }
  try {
    $cursor = $full
    while ($true) {
      if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparse' }
      $parent = Split-Path -Parent $cursor
      if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $cursor) { break }
      $cursor = $parent
    }
  } catch { throw "[$Code-reparse]" }
  if ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant() -cne $Sha256) { throw "[$Code-hash]" }
  return $full
}

function Test-MIR42SealCurrentIdentityHasEffectiveRights {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][Security.AccessControl.FileSystemRights]$RequestedRights)
  try {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    [int64]$denied = 0; [int64]$allowed = 0
    foreach ($rule in @((Get-Acl -LiteralPath $Path).GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))) {
      if ($principal.IsInRole([Security.Principal.SecurityIdentifier]$rule.IdentityReference)) {
        if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Deny) {
          $denied = $denied -bor [int64]$rule.FileSystemRights
        } elseif ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow) {
          $allowed = $allowed -bor [int64]$rule.FileSystemRights
        }
      }
    }
    return (($allowed -band (-bnot $denied) -band [int64]$RequestedRights) -ne 0)
  } catch {
    throw '[mir42-seal-external-trust-acl-unreadable]'
  }
}

function Test-MIR42SealCurrentIdentityCanWritePath {
  param([Parameter(Mandatory)][string]$Path,[switch]$Ancestor)
  $rights = if ($Ancestor) {
    [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
      [Security.AccessControl.FileSystemRights]::Delete -bor
      [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
      [Security.AccessControl.FileSystemRights]::TakeOwnership
  } else {
    [Security.AccessControl.FileSystemRights]::WriteData -bor
      [Security.AccessControl.FileSystemRights]::AppendData -bor
      [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
      [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
      [Security.AccessControl.FileSystemRights]::Delete -bor
      [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
      [Security.AccessControl.FileSystemRights]::TakeOwnership
  }
  return Test-MIR42SealCurrentIdentityHasEffectiveRights -Path $Path -RequestedRights $rights
}

function Resolve-MIR42SealExternalProtectedFile {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) { throw "[$Code-path]" }
  $full = [IO.Path]::GetFullPath($Path)
  Assert-MIR42SealExternalPathSeparatedFromRepository -RepoRoot $RepoRoot -Path $full -Code $Code
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[$Code-missing]" }
  $null = Resolve-MIR42SealImmutableFile -Path $full -Sha256 ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()) -Code $Code
  $cursor = $full; $ancestor = $false
  while ($true) {
    if (Test-MIR42SealCurrentIdentityCanWritePath -Path $cursor -Ancestor:$ancestor) { throw "[$Code-not-protected]" }
    $parent = Split-Path -Parent $cursor
    if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $cursor) { break }
    $cursor = $parent; $ancestor = $true
  }
  return $full
}

function Resolve-MIR42SealExternalProtectedDirectory {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) { throw "[$Code-path]" }
  $full = [IO.Path]::GetFullPath($Path)
  Assert-MIR42SealExternalPathSeparatedFromRepository -RepoRoot $RepoRoot -Path $full -Code $Code
  if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "[$Code-missing]" }
  try {
    $cursor = $full; $ancestor = $false
    while ($true) {
      if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparse' }
      if (Test-MIR42SealCurrentIdentityCanWritePath -Path $cursor -Ancestor:$ancestor) { throw 'not-protected' }
      $parent = Split-Path -Parent $cursor
      if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $cursor) { break }
      $cursor = $parent; $ancestor = $true
    }
  } catch {
    if ($_.Exception.Message -eq 'not-protected') { throw "[$Code-not-protected]" }
    throw "[$Code-reparse]"
  }
  return $full
}

function Get-MIR42SealAclAssessment {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  try {
    $acl = Get-Acl -LiteralPath $Path
    $ownerSid = ([Security.Principal.NTAccount]$acl.Owner).Translate([Security.Principal.SecurityIdentifier]).Value
    $rows = @(
      foreach ($rule in @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))) {
        [pscustomobject][ordered]@{
          sid = [string]$rule.IdentityReference.Value
          type = [string]$rule.AccessControlType
          rights = [Security.AccessControl.FileSystemRights]$rule.FileSystemRights
          inherited = [bool]$rule.IsInherited
        }
      }
    )
    return [pscustomobject][ordered]@{inheritance_protected=[bool]$acl.AreAccessRulesProtected;owner_sid=[string]$ownerSid;rows=$rows}
  } catch { throw "[$Code-acl-unreadable]" }
}

function New-MIR42T16AclContract {
  param([Parameter(Mandatory)][string]$ApprovedOwnerSid,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ApprovedMutationSids)
  $broad = @('S-1-1-0','S-1-5-11','S-1-5-32-545','S-1-5-32-546')
  $mutators = @($ApprovedMutationSids | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  if ($ApprovedOwnerSid -notmatch '^S-1-' -or $mutators.Count -eq 0 -or $mutators.Count -ne $ApprovedMutationSids.Count -or
      $ApprovedOwnerSid -notin $mutators -or @($mutators | Where-Object { $_ -notmatch '^S-1-' -or $_ -in $broad }).Count -ne 0) {
    throw '[mir42-seal-t16-acl-contract-human-input-required]'
  }
  $record = [pscustomobject][ordered]@{owner_sid=$ApprovedOwnerSid;mutation_sids=$mutators;broad_principals_forbidden=$broad}
  $canonical = ConvertTo-MIR4BootstrapCanonicalJson -Value @($mutators)
  return [pscustomobject][ordered]@{record=$record;custodian_sid_set_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical)))}
}

function Assert-MIR42SealT16AclContract {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$AclContract,[Parameter(Mandatory)][string]$Code)
  $assessment = Get-MIR42SealAclAssessment -Path $Path -Code $Code
  $record = $AclContract.record
  $approvedOwner = [string]$record.owner_sid
  $approvedMutators = @($record.mutation_sids | ForEach-Object { [string]$_ })
  $broad = @($record.broad_principals_forbidden | ForEach-Object { [string]$_ })
  if (-not [bool]$assessment.inheritance_protected) { throw "[$Code-acl-inheritance]" }
  if ([string]$assessment.owner_sid -cne $approvedOwner -or [string]$assessment.owner_sid -in $broad) { throw "[$Code-acl-owner]" }
  $actualAllowSids = @($assessment.rows | Where-Object { [string]$_.type -ceq 'Allow' } | ForEach-Object { [string]$_.sid } | Sort-Object -Unique)
  if (($actualAllowSids -join '|') -cne (($approvedMutators | Sort-Object -Unique) -join '|')) { throw "[$Code-acl-allow-sid]" }
  foreach ($row in @($assessment.rows)) {
    if ([bool]$row.inherited -or [string]$row.type -notin @('Allow','Deny') -or [string]$row.sid -in $broad) { throw "[$Code-acl-row]" }
    if ([string]$row.type -ceq 'Allow') {
      if ([string]$row.sid -notin $approvedMutators -or
          (([Security.AccessControl.FileSystemRights]$row.rights -band ([Security.AccessControl.FileSystemRights]::Modify -bor [Security.AccessControl.FileSystemRights]::FullControl)) -eq 0)) {
        throw "[$Code-acl-mutation]"
      }
    } elseif ([string]$row.sid -notin $approvedMutators) {
      throw "[$Code-acl-deny-sid]"
    }
  }
}

function Assert-MIR42SealT16AclContractTree {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$AclContract,[Parameter(Mandatory)][string]$Code)
  Assert-MIR42SealT16AclContract -Path $Path -AclContract $AclContract -Code $Code
  if (Test-Path -LiteralPath $Path -PathType Container) {
    foreach ($item in @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction Stop)) {
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "[$Code-reparse]" }
      Assert-MIR42SealT16AclContract -Path $item.FullName -AclContract $AclContract -Code $Code
    }
  }
}

function Assert-MIR42SealT16AclAncestorAssessment {
  param([Parameter(Mandatory)]$Assessment,[Parameter(Mandatory)]$AclContract,[Parameter(Mandatory)][string]$Code)
  $record = $AclContract.record
  $approvedOwner = [string]$record.owner_sid
  $approvedMutators = @($record.mutation_sids | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  $broad = @($record.broad_principals_forbidden | ForEach-Object { [string]$_ })
  $mutationRights = [Security.AccessControl.FileSystemRights]::WriteData -bor
    [Security.AccessControl.FileSystemRights]::AppendData -bor
    [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
    [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
    [Security.AccessControl.FileSystemRights]::Delete -bor
    [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
    [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
    [Security.AccessControl.FileSystemRights]::TakeOwnership
  if (-not [bool]$assessment.inheritance_protected) { throw "[$Code-acl-ancestor-inheritance]" }
  if ([string]$assessment.owner_sid -cne $approvedOwner -or [string]$assessment.owner_sid -in $broad) { throw "[$Code-acl-ancestor-owner]" }
  $actualMutationAllowSids = @(
    $assessment.rows | Where-Object {
      [string]$_.type -ceq 'Allow' -and
      (([Security.AccessControl.FileSystemRights]$_.rights -band $mutationRights) -ne 0)
    } | ForEach-Object { [string]$_.sid } | Sort-Object -Unique
  )
  if (($actualMutationAllowSids -join '|') -cne ($approvedMutators -join '|')) { throw "[$Code-acl-ancestor-allow-sid]" }
  foreach ($row in @($assessment.rows)) {
    if ([bool]$row.inherited -or [string]$row.type -notin @('Allow','Deny')) { throw "[$Code-acl-ancestor-row]" }
    $hasMutationRight = (([Security.AccessControl.FileSystemRights]$row.rights -band $mutationRights) -ne 0)
    if ([string]$row.type -ceq 'Allow' -and $hasMutationRight) {
      if ([string]$row.sid -in $broad -or [string]$row.sid -notin $approvedMutators -or
          (([Security.AccessControl.FileSystemRights]$row.rights -band ([Security.AccessControl.FileSystemRights]::Modify -bor [Security.AccessControl.FileSystemRights]::FullControl)) -eq 0)) {
        throw "[$Code-acl-ancestor-mutation]"
      }
    }
  }
}

function Assert-MIR42SealT16AclAncestorContract {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$AclContract,[Parameter(Mandatory)][string]$Code)
  $assessment = Get-MIR42SealAclAssessment -Path $Path -Code $Code
  Assert-MIR42SealT16AclAncestorAssessment -Assessment $assessment -AclContract $AclContract -Code $Code
}

function Assert-MIR42SealT16AclProtectedAncestors {
  param(
    [Parameter(Mandatory)][string]$ArtifactPath,
    [Parameter(Mandatory)][string]$ProtectedRootPath,
    [Parameter(Mandatory)]$AclContract,
    [Parameter(Mandatory)][string]$Code
  )
  $artifact = [IO.Path]::GetFullPath($ArtifactPath)
  $protectedRootFull = [IO.Path]::GetFullPath($ProtectedRootPath)
  if ($protectedRootFull -ceq [IO.Path]::GetPathRoot($protectedRootFull)) { throw "[$Code-protected-root-path]" }
  $protectedRoot = $protectedRootFull.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
  $relative = [IO.Path]::GetRelativePath($protectedRoot,$artifact)
  if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)) {
    throw "[$Code-protected-root-containment]"
  }
  $cursor = Split-Path -Parent $artifact
  while ($true) {
    if ([string]::IsNullOrWhiteSpace($cursor)) { throw "[$Code-protected-root-containment]" }
    $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "[$Code-reparse]" }
    Assert-MIR42SealT16AclAncestorContract -Path $cursor -AclContract $AclContract -Code $Code
    if ($cursor -ceq $protectedRoot) { break }
    $parent = Split-Path -Parent $cursor
    if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $cursor) { throw "[$Code-protected-root-containment]" }
    $cursor = $parent
  }
}

function Resolve-MIR42SealImmutableVolumeShareAnchor {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) { throw "[$Code-path]" }
  $full = [IO.Path]::GetFullPath($Path)
  $root = [IO.Path]::GetPathRoot($full)
  if ($full.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)) -cne $root.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))) {
    throw "[$Code-volume-or-share-boundary]"
  }
  if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "[$Code-missing]" }
  try {
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparse' }
    if (Test-MIR42SealCurrentIdentityCanWritePath -Path $full) { throw 'not-protected' }
  } catch {
    if ($_.Exception.Message -eq 'not-protected') { throw "[$Code-not-protected]" }
    throw "[$Code-reparse]"
  }
  return $full
}

function Assert-MIR42SealT16AclImmutableAnchorAssessment {
  param([Parameter(Mandatory)]$Assessment,[Parameter(Mandatory)]$AclContract,[Parameter(Mandatory)][string]$Code)
  $approvedMutators = @($AclContract.record.mutation_sids | ForEach-Object { [string]$_ })
  $broad = @($AclContract.record.broad_principals_forbidden | ForEach-Object { [string]$_ })
  $mutationRights = [Security.AccessControl.FileSystemRights]::WriteData -bor
    [Security.AccessControl.FileSystemRights]::AppendData -bor
    [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
    [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
    [Security.AccessControl.FileSystemRights]::Delete -bor
    [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
    [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
    [Security.AccessControl.FileSystemRights]::TakeOwnership
  if ([string]$Assessment.owner_sid -in $broad -or [string]$Assessment.owner_sid -notin $approvedMutators) {
    throw "[$Code-acl-anchor-owner]"
  }
  foreach ($row in @($Assessment.rows)) {
    if ([string]$row.type -notin @('Allow','Deny')) { throw "[$Code-acl-anchor-row]" }
    if ([string]$row.type -ceq 'Allow' -and (([Security.AccessControl.FileSystemRights]$row.rights -band $mutationRights) -ne 0) -and
        ([string]$row.sid -in $broad -or [string]$row.sid -notin $approvedMutators)) {
      throw "[$Code-acl-anchor-mutation]"
    }
  }
}

function Assert-MIR42SealT16AclRootToImmutableAnchor {
  param(
    [Parameter(Mandatory)][string]$ProtectedRootPath,
    [Parameter(Mandatory)][string]$ImmutableAnchorPath,
    [Parameter(Mandatory)]$AclContract,
    [Parameter(Mandatory)][string]$Code
  )
  $protectedRoot = [IO.Path]::GetFullPath($ProtectedRootPath)
  $anchor = [IO.Path]::GetFullPath($ImmutableAnchorPath)
  $relative = [IO.Path]::GetRelativePath($anchor,$protectedRoot)
  if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)) {
    throw "[$Code-immutable-anchor-containment]"
  }
  $cursor = Split-Path -Parent $protectedRoot
  while ($true) {
    if ([string]::IsNullOrWhiteSpace($cursor)) { throw "[$Code-immutable-anchor-containment]" }
    $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "[$Code-reparse]" }
    $assessment = Get-MIR42SealAclAssessment -Path $cursor -Code $Code
    if ($cursor -ceq $anchor) {
      Assert-MIR42SealT16AclImmutableAnchorAssessment -Assessment $assessment -AclContract $AclContract -Code $Code
      break
    }
    Assert-MIR42SealT16AclAncestorAssessment -Assessment $assessment -AclContract $AclContract -Code $Code
    $parent = Split-Path -Parent $cursor
    if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $cursor) { throw "[$Code-immutable-anchor-containment]" }
    $cursor = $parent
  }
}

function Get-MIR42SealGitBlobSha256 {
  param([Parameter(Mandatory)][string]$RepositoryPath,[Parameter(Mandatory)][string]$Revision,[Parameter(Mandatory)][string]$Code)
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = 'git'; $info.UseShellExecute = $false; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
  foreach ($argument in @('-C',$RepositoryPath,'show',$Revision)) { $null = $info.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
  try {
    if (-not $process.Start()) { throw "[$Code-start]" }
    $bytes = [IO.MemoryStream]::new()
    try { $process.StandardOutput.BaseStream.CopyTo($bytes); $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes.ToArray())) }
    finally { $bytes.Dispose() }
    $stderr = $process.StandardError.ReadToEnd(); $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "[$Code-show] $stderr" }
    return $digest
  } finally { $process.Dispose() }
}

function Assert-MIR42SealExternalVerifierAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Verifier,[Parameter(Mandatory)][string]$Code)
  Assert-MIR42SealPropertyNames -Value $Verifier -Expected @('source','dependencies') -Code "$Code-shape"
  Assert-MIR42SealPropertyNames -Value $Verifier.source -Expected @('commit','tree') -Code "$Code-source-shape"
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $dirty = @(& git -C $repo status --porcelain=v1 --untracked-files=all)
  if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw "[$Code-source-dirty]" }
  $commit = (& git -C $repo rev-parse HEAD).Trim()
  $tree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  if ($LASTEXITCODE -ne 0 -or [string]$Verifier.source.commit -cne $commit -or [string]$Verifier.source.tree -cne $tree) {
    throw "[$Code-source-binding]"
  }
  $rows = @($Verifier.dependencies)
  $actualPaths = @($rows | ForEach-Object { [string]$_.path })
  if ($rows.Count -ne $script:MIR42SealVerifierDependencyPaths.Count -or ($actualPaths -join '|') -cne ($script:MIR42SealVerifierDependencyPaths -join '|')) {
    throw "[$Code-dependency-set]"
  }
  foreach ($row in $rows) {
    Assert-MIR42SealPropertyNames -Value $row -Expected @('path','sha256') -Code "$Code-dependency-shape"
    $relative = [string]$row.path
    $full = Join-Path $repo $relative
    if ($relative -match '(^|[\\/])\.\.([\\/]|$)' -or -not (Test-Path -LiteralPath $full -PathType Leaf) -or [string]$row.sha256 -notmatch '^[A-F0-9]{64}$') {
      throw "[$Code-dependency-path]"
    }
    $currentSha = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()
    $committedSha = Get-MIR42SealGitBlobSha256 -RepositoryPath $repo -Revision ($commit + ':' + $relative) -Code "$Code-dependency"
    if ($currentSha -cne [string]$row.sha256 -or $committedSha -cne [string]$row.sha256) { throw "[$Code-dependency-hash]" }
  }
  return [pscustomobject][ordered]@{source=[pscustomobject][ordered]@{commit=$commit;tree=$tree};dependencies=@($rows)}
}

function Assert-MIR42SealAuthorizedLedgerCommitSignature {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RepositoryPath,
    [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)]$AuthorizedSigner,
    [Parameter(Mandatory)][string]$SshKeygenPath
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $scratchRoot = Assert-MIR4NoReparseAncestors -Root $repo -Path (Join-Path $repo 'build/tmp')
  if (-not (Test-Path -LiteralPath $scratchRoot -PathType Container)) { New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null }
  $scratch = Assert-MIR4NoReparseAncestors -Root $scratchRoot -Path (Join-Path $scratchRoot ('mir42-ledger-commit-' + [guid]::NewGuid().ToString('N')))
  try {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    $publicKeyPath = Join-Path $scratch 'ledger.pub'; $allowedSignersPath = Join-Path $scratch 'allowed-signers'
    [IO.File]::WriteAllText($publicKeyPath, ([string]$AuthorizedSigner.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    if ((Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKeyPath) -cne [string]$AuthorizedSigner.fingerprint) {
      throw '[mir42-seal-external-t16-ledger-commit-key-fingerprint]'
    }
    [IO.File]::WriteAllText($allowedSignersPath, "$([string]$AuthorizedSigner.principal) namespaces=`"git`" $([string]$AuthorizedSigner.public_key)`n", [Text.UTF8Encoding]::new($false))
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = 'git'; $info.UseShellExecute = $false; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    foreach ($argument in @('-C',$RepositoryPath,'-c','gpg.format=ssh','-c',("gpg.ssh.allowedSignersFile=" + $allowedSignersPath),'verify-commit',$Commit)) { $null = $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
    try {
      if (-not $process.Start()) { throw '[mir42-seal-external-t16-ledger-commit-start]' }
      $null = $process.StandardOutput.ReadToEnd(); $stderr = $process.StandardError.ReadToEnd(); $process.WaitForExit()
      if ($process.ExitCode -ne 0) { throw "[mir42-seal-external-t16-ledger-commit-signature] $stderr" }
    } finally { $process.Dispose() }
  } finally {
    if (Test-Path -LiteralPath $scratch) { Remove-MIR4BuildTree -OutputRoot $scratchRoot -Path $scratch }
  }
}

function Get-MIR42T16TrustRootSignaturePayload {
  param([Parameter(Mandatory)]$Record)
  $payload = [ordered]@{
    schema = [int]$Record.schema
    kind = [string]$Record.kind
    status = [string]$Record.status
    release_line = [string]$Record.release_line
    turn = [string]$Record.turn
    scope = [string]$Record.scope
    signing_ceremony = $Record.signing_ceremony
    authorized_signer = $Record.authorized_signer
    independent_reviewer = $Record.independent_reviewer
    recovery = $Record.recovery
    operator_trust = $Record.operator_trust
    verifier = $Record.verifier
    ledger = $Record.ledger
  }
  if ([string]$Record.kind -ceq 'MIR42NineTargetExternalT16LedgerTrustRootV1') {
    $payload.key_policy_interpretation = $Record.key_policy_interpretation
    $payload.human_acceptance = $Record.human_acceptance
  }
  return [pscustomobject]$payload
}

function Assert-MIR42NineTargetSigningPolicyAcceptance {
  param([Parameter(Mandatory)]$Record)
  # This current, operator-signed interpretation is mandatory for nine targets.
  # The old four-target ceremony is provenance, never implicit permission to
  # reuse its dedicated signer under the preparation's reused-key prohibition.
  if ([string]$Record.key_policy_interpretation -cne 'existing-MIR-dedicated-signer-continuity') {
    throw '[mir42-nine-seal-signing-policy-interpretation]'
  }
  Assert-MIR42SealPropertyNames -Value $Record.human_acceptance -Expected @('maintainer','decided_at','decision') -Code 'mir42-nine-seal-signing-human-acceptance-shape'
  $acceptedAt = [DateTimeOffset]::MinValue
  if ([string]$Record.human_acceptance.decision -cne 'ACCEPTED' -or
      [string]::IsNullOrWhiteSpace([string]$Record.human_acceptance.maintainer) -or
      [string]$Record.human_acceptance.decided_at -notmatch '^\d{4}-\d{2}-\d{2}T' -or
      -not [DateTimeOffset]::TryParse([string]$Record.human_acceptance.decided_at, [ref]$acceptedAt)) {
    throw '[mir42-nine-seal-signing-current-human-acceptance]'
  }
}

function Get-MIR42ExternalT16LedgerTrustRoot {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$T16TrustRootPath,
    [Parameter(Mandatory)][string]$OperatorTrustSourcePath,
    [Parameter(Mandatory)][string]$ProtectedRootPath,
    [Parameter(Mandatory)][string]$ImmutableAnchorPath,
    [Parameter(Mandatory)]$AclContract,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [ValidateSet('four-target','nine-target')][string]$Scope='four-target'
  )
  if ([string]::IsNullOrWhiteSpace($T16TrustRootPath) -or [string]::IsNullOrWhiteSpace($OperatorTrustSourcePath) -or [string]::IsNullOrWhiteSpace($SshKeygenPath)) {
    throw '[mir42-seal-external-t16-trust-root-required]'
  }
  $immutableAnchor = Resolve-MIR42SealImmutableVolumeShareAnchor -Path $ImmutableAnchorPath -Code 'mir42-seal-external-t16-immutable-anchor'
  $protectedRoot = Resolve-MIR42SealExternalProtectedDirectory -RepoRoot $RepoRoot -Path $ProtectedRootPath -Code 'mir42-seal-external-t16-protected-root'
  Assert-MIR42SealT16AclContract -Path $protectedRoot -AclContract $AclContract -Code 'mir42-seal-external-t16-protected-root'
  Assert-MIR42SealT16AclRootToImmutableAnchor -ProtectedRootPath $protectedRoot -ImmutableAnchorPath $immutableAnchor -AclContract $AclContract -Code 'mir42-seal-external-t16-protected-root'
  $trustPath = Resolve-MIR42SealExternalProtectedFile -RepoRoot $RepoRoot -Path $T16TrustRootPath -Code 'mir42-seal-external-t16-trust-root'
  $operatorPath = Resolve-MIR42SealExternalProtectedFile -RepoRoot $RepoRoot -Path $OperatorTrustSourcePath -Code 'mir42-seal-external-operator-trust-source'
  $trust = Read-MIR42SealRecord -Path $trustPath -Code 'mir42-seal-external-t16-trust-root'
  $operator = Read-MIR42SealRecord -Path $operatorPath -Code 'mir42-seal-external-operator-trust-source'
  Assert-MIR42SealT16AclContract -Path $trust.path -AclContract $AclContract -Code 'mir42-seal-external-t16-trust-root'
  Assert-MIR42SealT16AclContract -Path $operator.path -AclContract $AclContract -Code 'mir42-seal-external-operator-trust-source'
  Assert-MIR42SealT16AclProtectedAncestors -ArtifactPath $trust.path -ProtectedRootPath $protectedRoot -AclContract $AclContract -Code 'mir42-seal-external-t16-trust-root'
  Assert-MIR42SealT16AclProtectedAncestors -ArtifactPath $operator.path -ProtectedRootPath $protectedRoot -AclContract $AclContract -Code 'mir42-seal-external-operator-trust-source'
  $record = $trust.record
  $operatorRecord = $operator.record
  Assert-MIR42SealPropertyNames -Value $operatorRecord -Expected @('schema','kind','status','operator','namespaces','record_sha256') -Code 'mir42-seal-external-operator-trust-source-shape'
  Assert-MIR42SealPropertyNames -Value $operatorRecord.operator -Expected @('identity','algorithm','public_key','fingerprint') -Code 'mir42-seal-external-operator-trust-source-operator-shape'
  if ([int]$operatorRecord.schema -ne 1 -or [string]$operatorRecord.kind -cne 'MIR42ExternalOperatorTrustSourceV1' -or
      [string]$operatorRecord.status -cne 'active-external-protected-operator-trust-source' -or
      [string]$operatorRecord.operator.algorithm -cne 'ssh-ed25519' -or
      [string]$operatorRecord.operator.public_key -notmatch '^ssh-ed25519\s+' -or
      [string]$operatorRecord.operator.fingerprint -notmatch '^SHA256:' -or
      (@($operatorRecord.namespaces | ForEach-Object { [string]$_ }) -join '|') -cne 'mir4-t16-trust-root') {
    throw '[mir42-seal-external-operator-trust-source-state]'
  }
  $contract = Get-MIR42SealScopeContract -Scope $Scope
  $trustProperties = @('schema','kind','status','release_line','turn','scope','signing_ceremony','authorized_signer','independent_reviewer','recovery','operator_trust','verifier','ledger','trust_signature','record_sha256')
  if ($Scope -ceq 'nine-target') { $trustProperties += @('key_policy_interpretation','human_acceptance') }
  Assert-MIR42SealPropertyNames -Value $record -Expected $trustProperties -Code 'mir42-seal-external-t16-trust-root-shape'
  Assert-MIR42SealPropertyNames -Value $record.signing_ceremony -Expected @('path','sha256','record_sha256') -Code 'mir42-seal-external-t16-trust-root-signing-shape'
  Assert-MIR42SealPropertyNames -Value $record.authorized_signer -Expected @('principal','algorithm','public_key','fingerprint','namespaces') -Code 'mir42-seal-external-t16-trust-root-signer-shape'
  Assert-MIR42SealPropertyNames -Value $record.independent_reviewer -Expected @('identity','public_key','fingerprint') -Code 'mir42-seal-external-t16-trust-root-reviewer-shape'
  Assert-MIR42SealPropertyNames -Value $record.operator_trust -Expected @('path','sha256','record_sha256') -Code 'mir42-seal-external-t16-trust-root-operator-binding-shape'
  Assert-MIR42SealPropertyNames -Value $record.verifier -Expected @('source','dependencies') -Code 'mir42-seal-external-t16-trust-root-verifier-shape'
  Assert-MIR42SealPropertyNames -Value $record.ledger -Expected @('repository_path','ref','commit','event_path','event_sha256') -Code 'mir42-seal-external-t16-trust-root-ledger-shape'
  Assert-MIR42SealPropertyNames -Value $record.trust_signature -Expected @('identity','namespace','signature_path','signature_sha256','payload_sha256') -Code 'mir42-seal-external-t16-trust-root-signature-shape'
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne [string]$contract.trust_root_kind -or
      [string]$record.status -cne 'MIR-4.2-T16-PROTECTED-SIGNING-RECOVERY-ACCEPTED' -or [string]$record.release_line -cne '4.2' -or
      [string]$record.turn -cne 'T16' -or [string]$record.scope -cne ($Scope + '-release-cut') -or
      [string]$record.authorized_signer.algorithm -cne 'ssh-ed25519' -or [string]$record.authorized_signer.public_key -notmatch '^ssh-ed25519\s+' -or
      [string]$record.authorized_signer.fingerprint -notmatch '^SHA256:' -or
      (@($record.authorized_signer.namespaces | ForEach-Object { [string]$_ }) -join '|') -cne 'mir4-source|mir4-target|mir4-ledger' -or
      [string]$record.independent_reviewer.public_key -notmatch '^ssh-ed25519\s+' -or [string]$record.independent_reviewer.fingerprint -notmatch '^SHA256:' -or
      [string]$record.operator_trust.path -cne $operator.path -or [string]$record.operator_trust.sha256 -cne $operator.sha256 -or
      [string]$record.operator_trust.record_sha256 -cne [string]$operator.record.record_sha256 -or
      [string]$record.trust_signature.identity -cne [string]$operatorRecord.operator.identity -or
      [string]$record.trust_signature.namespace -cne 'mir4-t16-trust-root' -or
      [string]$record.trust_signature.signature_sha256 -notmatch '^[A-F0-9]{64}$') {
    throw '[mir42-seal-external-t16-trust-root-state]'
  }
  if ($Scope -ceq 'nine-target') { Assert-MIR42NineTargetSigningPolicyAcceptance -Record $record }
  $verifier = Assert-MIR42SealExternalVerifierAuthority -RepoRoot $RepoRoot -Verifier $record.verifier -Code 'mir42-seal-external-t16-trust-root-verifier'
  $ledgerPath = Resolve-MIR42SealExternalProtectedDirectory -RepoRoot $RepoRoot -Path ([string]$record.ledger.repository_path) -Code 'mir42-seal-external-t16-ledger'
  Assert-MIR42SealT16AclContractTree -Path $ledgerPath -AclContract $AclContract -Code 'mir42-seal-external-t16-ledger'
  Assert-MIR42SealT16AclProtectedAncestors -ArtifactPath $ledgerPath -ProtectedRootPath $protectedRoot -AclContract $AclContract -Code 'mir42-seal-external-t16-ledger'
  if ([string]$record.ledger.ref -notmatch '^refs/heads/release-ledger/mir4$' -or
      [string]$record.ledger.commit -notmatch '^[0-9a-f]{40}$' -or [string]$record.ledger.event_path -match '(^|[\\/])\.\.([\\/]|$)' -or
      [IO.Path]::IsPathRooted([string]$record.ledger.event_path) -or [string]$record.ledger.event_sha256 -cne [string]$trust.sha256) {
    throw '[mir42-seal-external-t16-ledger-state]'
  }
  $refCommit = (& git -C $ledgerPath rev-parse ([string]$record.ledger.ref) 2>$null).Trim()
  $revision = ([string]$record.ledger.commit) + ':' + ([string]$record.ledger.event_path)
  $blobSha256 = Get-MIR42SealGitBlobSha256 -RepositoryPath $ledgerPath -Revision $revision -Code 'mir42-seal-external-t16-ledger'
  if ($LASTEXITCODE -ne 0 -or $refCommit -cne [string]$record.ledger.commit -or
      $blobSha256 -cne [string]$trust.sha256) {
    throw '[mir42-seal-external-t16-ledger-binding]'
  }
  Assert-MIR42SealAuthorizedLedgerCommitSignature -RepoRoot $RepoRoot -RepositoryPath $ledgerPath -Commit ([string]$record.ledger.commit) -AuthorizedSigner $record.authorized_signer -SshKeygenPath $SshKeygenPath
  $signaturePath = Resolve-MIR42SealExternalProtectedFile -RepoRoot $RepoRoot -Path ([string]$record.trust_signature.signature_path) -Code 'mir42-seal-external-t16-trust-signature'
  Assert-MIR42SealT16AclContract -Path $signaturePath -AclContract $AclContract -Code 'mir42-seal-external-t16-trust-signature'
  Assert-MIR42SealT16AclProtectedAncestors -ArtifactPath $signaturePath -ProtectedRootPath $protectedRoot -AclContract $AclContract -Code 'mir42-seal-external-t16-trust-signature'
  if ((Get-FileHash -LiteralPath $signaturePath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$record.trust_signature.signature_sha256) {
    throw '[mir42-seal-external-t16-trust-signature-hash]'
  }
  $payload = ConvertTo-MIR4BootstrapCanonicalJson -Value (Get-MIR42T16TrustRootSignaturePayload -Record $record)
  $payloadSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payload)))
  if ([string]$record.trust_signature.payload_sha256 -cne $payloadSha) { throw '[mir42-seal-external-t16-trust-signature-payload]' }
  $scratchRoot = Assert-MIR4NoReparseAncestors -Root $RepoRoot -Path (Join-Path $RepoRoot 'build/tmp')
  if (-not (Test-Path -LiteralPath $scratchRoot -PathType Container)) { New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null }
  $scratch = Assert-MIR4NoReparseAncestors -Root $scratchRoot -Path (Join-Path $scratchRoot ('mir42-t16-trust-root-' + [guid]::NewGuid().ToString('N')))
  try {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    $publicKeyPath = Join-Path $scratch 'operator.pub'; $authorizedSignerPath = Join-Path $scratch 'authorized-signer.pub'; $reviewerPath = Join-Path $scratch 'reviewer.pub'; $payloadPath = Join-Path $scratch 'trust-root.json'
    [IO.File]::WriteAllText($publicKeyPath, ([string]$operatorRecord.operator.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($authorizedSignerPath, ([string]$record.authorized_signer.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($reviewerPath, ([string]$record.independent_reviewer.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($payloadPath, $payload, [Text.UTF8Encoding]::new($false))
    if ((Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKeyPath) -cne [string]$operatorRecord.operator.fingerprint -or
        (Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $authorizedSignerPath) -cne [string]$record.authorized_signer.fingerprint -or
        (Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $reviewerPath) -cne [string]$record.independent_reviewer.fingerprint -or
        -not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKeyPath -Identity ([string]$operatorRecord.operator.identity) -Namespace 'mir4-t16-trust-root' -PayloadPath $payloadPath -SignaturePath $signaturePath -ScratchRoot (Join-Path $scratch 'verify'))) {
      throw '[mir42-seal-external-t16-trust-signature-verification]'
    }
  } finally {
    if (Test-Path -LiteralPath $scratch) { Remove-MIR4BuildTree -OutputRoot $scratchRoot -Path $scratch }
  }
  return [pscustomobject][ordered]@{path=$trust.path;sha256=$trust.sha256;record=$record;operator=$operator;verifier=$verifier;protected_root=$protectedRoot;immutable_anchor=$immutableAnchor;acl_contract=$AclContract}
}

function Get-MIR42SealCandidateConstructionVersionContract {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Manifest)
  $contract = Get-MIR42CandidateConstructionVersionContract -RepoRoot $RepoRoot -Manifest $Manifest
  if (-not (Test-MIR4BootstrapRecordHash -Record $Manifest)) { throw '[mir42-seal-candidate-record-hash]' }
  if (-not ($Manifest | ConvertTo-Json -Depth 100 | Test-Json -SchemaFile ([string]$contract.schema_path) -ErrorAction SilentlyContinue)) {
    throw '[mir42-seal-candidate-manifest-schema]'
  }
  return $contract
}

# A 4.3 historical candidate preserves its construction manifest beside the
# selected ZIP.  The manifest's self hash alone is a logical identity; bind it
# to the copied file's raw identity as well, so a reformatted but otherwise
# self-consistent receipt cannot be substituted at native-reader time.
function Get-MIR42HistoricalMaterializerReceiptCustody {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)]$Row
  )

  foreach ($field in @('historical_materializer_manifest_sha256','historical_materializer_manifest')) {
    if ($Row.PSObject.Properties.Name -notcontains $field) {
      throw "[mir42-seal-candidate-historical-receipt-field] $Target/$field"
    }
  }
  $descriptor = $Row.historical_materializer_manifest
  if ($null -eq $descriptor) {
    throw "[mir42-seal-candidate-historical-receipt-shape] $Target"
  }
  Assert-MIR42SealPropertyNames -Value $descriptor -Expected @('path','bytes','sha256','record_sha256') -Code 'mir42-seal-candidate-historical-receipt-shape'
  $expectedPath = "materializations/$Target.json"
  if ([string]$descriptor.path -cne $expectedPath) {
    throw "[mir42-seal-candidate-historical-receipt-path] $Target"
  }
  [int64]$expectedBytes = 0
  if (-not [int64]::TryParse([string]$descriptor.bytes, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$expectedBytes) -or
      $expectedBytes -le 0) {
    throw "[mir42-seal-candidate-historical-receipt-bytes] $Target"
  }
  foreach ($field in @('sha256','record_sha256')) {
    if ([string]$descriptor.$field -notmatch '^[A-F0-9]{64}$') {
      throw "[mir42-seal-candidate-historical-receipt-$field] $Target"
    }
  }
  if ([string]$Row.historical_materializer_manifest_sha256 -notmatch '^[A-F0-9]{64}$' -or
      [string]$Row.historical_materializer_manifest_sha256 -cne [string]$descriptor.record_sha256) {
    throw "[mir42-seal-candidate-historical-receipt-legacy-pin] $Target"
  }
  $receiptPath = Resolve-MIR42SealContainedArtifactPath -Root $Root -RelativePath $expectedPath -Code 'mir42-seal-candidate-historical-receipt'
  if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
    throw "[mir42-seal-candidate-historical-receipt-missing] $Target"
  }
  $raw = Get-MIR4RawFileIdentity -Path $receiptPath
  if ([int64]$raw.bytes -ne $expectedBytes) {
    throw "[mir42-seal-candidate-historical-receipt-bytes] $Target"
  }
  if ([string]$raw.sha256 -cne [string]$descriptor.sha256) {
    throw "[mir42-seal-candidate-historical-receipt-sha256] $Target"
  }
  $receipt = Read-MIR42SealRecord -Path $receiptPath -Code 'mir42-seal-candidate-historical-receipt'
  if ([string]$receipt.record.record_sha256 -cne [string]$descriptor.record_sha256) {
    throw "[mir42-seal-candidate-historical-receipt-record-sha256] $Target"
  }
  return [pscustomobject][ordered]@{
    descriptor = [pscustomobject][ordered]@{
      path = $expectedPath
      bytes = $expectedBytes
      sha256 = [string]$descriptor.sha256
      record_sha256 = [string]$descriptor.record_sha256
    }
    path = $receipt.path
  }
}

function Get-MIR42ExactFourTargetCandidate {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$CandidateManifestPath)
  $candidateInput = Read-MIR42SealRecord -Path $CandidateManifestPath -Code 'mir42-seal-candidate'
  $candidate = $candidateInput.record
  $versionContract = Get-MIR42SealCandidateConstructionVersionContract -RepoRoot $RepoRoot -Manifest $candidate
  if ($candidate.PSObject.Properties.Name -notcontains 'target_authority') { throw '[mir42-seal-candidate-target-authority-missing]' }
  $targetScope = Get-MIR42SealCandidateTargetScope -Rows @($candidate.targets) -Code 'mir42-seal-candidate-targets'
  $authorityScope = Get-MIR42SealCandidateTargetScope -Rows @($candidate.target_authority) -Code 'mir42-seal-candidate-target-authority'
  $expectedStatus = if ($targetScope -ceq 'four-target') {
    'private-deterministic-four-target-candidate-built-unqualified'
  } else {
    'private-deterministic-nine-target-candidate-built-unqualified'
  }
  if ([string]$candidate.kind -cne [string]$versionContract.manifest_kind -or
      $authorityScope -cne $targetScope -or [string]$candidate.status -cne $expectedStatus -or
      -not [bool]$candidate.build_complete -or
      [string]$candidate.qualification -cne 'not-performed' -or
      [bool]$candidate.publication_authorized) {
    throw '[mir42-seal-candidate-state]'
  }
  $candidateSource = [pscustomobject][ordered]@{
    commit = [string]$candidate.source.commit
    tree = [string]$candidate.source.tree
    package_source_sha256 = [string]$candidate.package_source_sha256
  }
  $source = Assert-MIR42SealSource -RepoRoot $RepoRoot -Source $candidateSource -Code 'mir42-seal-candidate'
  $root = Split-Path -Parent $candidateInput.path
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($target in @($candidate.targets)) {
    foreach ($field in @('target','distribution_version','target_row_path','asset','content_sha256','entry_count')) {
      if ($target.PSObject.Properties.Name -notcontains $field) { throw "[mir42-seal-candidate-target-field] $([string]$target.target)/$field" }
    }
    if (-not [bool]$target.asset.bytes -or [string]$target.asset.sha256 -notmatch '^[A-F0-9]{64}$') {
      throw "[mir42-seal-candidate-asset-shape] $([string]$target.target)"
    }
    $assetPath = Resolve-MIR42SealContainedArtifactPath -Root $root -RelativePath ([string]$target.asset.path) -Code 'mir42-seal-candidate-asset'
    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$target.asset.sha256 -or
        [int64](Get-Item -LiteralPath $assetPath).Length -ne [int64]$target.asset.bytes) {
      throw "[mir42-seal-candidate-asset-drift] $([string]$target.target)"
    }
    $rowPath = Resolve-MIR42SealContainedArtifactPath -Root $root -RelativePath ([string]$target.target_row_path) -Code 'mir42-seal-candidate-target-row'
    $rowInput = Read-MIR42SealRecord -Path $rowPath -Code 'mir42-seal-target-row'
    $row = $rowInput.record
    if ([int]$row.schema -ne 1 -or [string]$row.kind -cne 'MIR42FourTargetCandidateRowV1') {
      throw "[mir42-seal-candidate-target-row-schema] $([string]$target.target)"
    }
    $expected = Get-MIR42ReleaseTargetIdentity -RepoRoot $RepoRoot -Target ([string]$target.target) -SourceVersion ([string]$versionContract.source_version)
    $authorityRow = @($candidate.target_authority | Where-Object { [string]$_.target -ceq [string]$target.target })
    if ($authorityRow.Count -ne 1) { throw "[mir42-seal-candidate-target-authority-binding] $([string]$target.target)" }
    foreach ($field in @('target','target_id','source_version','distribution_version')) {
      if ($authorityRow[0].PSObject.Properties.Name -notcontains $field) { throw "[mir42-seal-candidate-target-authority-field] $([string]$target.target)/$field" }
    }
    if ([string]$authorityRow[0].target -cne [string]$expected.target -or
        [string]$authorityRow[0].target_id -cne [string]$expected.target_id -or
        [string]$authorityRow[0].source_version -cne [string]$expected.source_version -or
        [string]$authorityRow[0].distribution_version -cne [string]$expected.distribution_version) {
      throw "[mir42-seal-candidate-target-authority-binding] $([string]$target.target)"
    }
    try { $inventory = Get-MIR4ArchiveInventory -Path $assetPath }
    catch { throw "[mir42-seal-candidate-archive-invalid] $([string]$target.target)" }
    if ([IO.Path]::GetFileName($assetPath) -cne [string]$expected.package_name -or
        [string]$inventory.root -cne [string]$expected.distribution_root -or
        [string]$target.distribution_version -cne [string]$expected.distribution_version -or
        [string]$inventory.archive_sha256 -cne [string]$target.asset.sha256 -or
        [string]$inventory.content_sha256 -cne [string]$target.content_sha256 -or
        [int]$inventory.entry_count -ne [int]$target.entry_count) {
      throw "[mir42-seal-candidate-package-identity] $([string]$target.target)"
    }
    Assert-MIR42FourTargetPackageExcludedSurface -Inventory $inventory -Target ([string]$target.target)
    try { $info = Read-MIR4ArchiveText -Path $assetPath -RelativePath 'info.json' | ConvertFrom-Json -Depth 20 -DateKind String }
    catch { throw "[mir42-seal-candidate-info-json] $([string]$target.target)" }
    if ([string]$info.name -cne 'more-infinite-research' -or [string]$info.version -cne [string]$expected.distribution_version -or
        [string]$info.factorio_version -cne ([string]$expected.target_id -replace '^factorio-', '')) {
      throw "[mir42-seal-candidate-info-identity] $([string]$target.target)"
    }
    foreach ($field in @('source','package_authority_sha256','package_source_sha256')) {
      if ($row.PSObject.Properties.Name -notcontains $field) { throw "[mir42-seal-candidate-target-row-field] $([string]$target.target)/$field" }
    }
    foreach ($field in @('commit','tree')) {
      if ($row.source.PSObject.Properties.Name -notcontains $field) { throw "[mir42-seal-candidate-target-row-source-field] $([string]$target.target)/$field" }
    }
    if ([string]$row.target -cne [string]$target.target -or
        [string]$row.source_version -cne [string]$versionContract.source_version -or
        [string]$row.distribution_version -cne [string]$target.distribution_version -or
        [string]$row.asset.sha256 -cne [string]$target.asset.sha256 -or
        [string]$row.content_sha256 -cne [string]$target.content_sha256 -or
        [int]$row.entry_count -ne [int]$target.entry_count -or
        -not [bool]$row.deterministic_archive_bytes -or -not [bool]$row.package_excluded_surface -or
        [string]$row.build_a_sha256 -cne [string]$target.asset.sha256 -or
        [string]$row.build_b_sha256 -cne [string]$target.asset.sha256 -or
        [string]$row.source.commit -cne [string]$Candidate.source.commit -or
        [string]$row.source.tree -cne [string]$Candidate.source.tree -or
        [string]$row.package_authority_sha256 -cne [string]$candidate.package_authority_sha256 -or
        [string]$row.package_source_sha256 -cne [string]$candidate.package_source_sha256) {
      throw "[mir42-seal-candidate-target-row-drift] $([string]$target.target)"
    }
    $historicalReceipt = $null
    if ($expected.PSObject.Properties.Name -contains 'target_record_path') {
      foreach ($field in @('materializer','base_materializer_target','target_record','factorio_line','public_output_authorized','publication_authorized')) {
        if ($row.PSObject.Properties.Name -notcontains $field) { throw "[mir42-seal-candidate-historical-row-field] $([string]$target.target)/$field" }
      }
      Assert-MIR42SealPropertyNames -Value $row.target_record -Expected @('path','sha256') -Code 'mir42-seal-candidate-historical-target-record-shape'
      $targetRecordPath = Resolve-MIR42SealContainedArtifactPath -Root $RepoRoot -RelativePath ([string]$expected.target_record_path) -Code 'mir42-seal-candidate-historical-target-record'
      $targetRecord = Read-MIR42SealRecord -Path $targetRecordPath -Code 'mir42-seal-candidate-historical-target-record'
      if ([string]$row.materializer -cne 'historical-playtest-target' -or [string]$row.base_materializer_target -cne 'f100' -or
          [string]$row.factorio_line -cne ([string]$expected.target_id -replace '^factorio-', '') -or
          [bool]$row.public_output_authorized -or [bool]$row.publication_authorized -or
          [string]$row.target_record.path -cne [string]$expected.target_record_path -or
          [string]$row.target_record.sha256 -cne [string]$expected.target_record_record_sha256 -or
          [string]$targetRecord.record.record_sha256 -cne [string]$expected.target_record_record_sha256 -or
          [string]$targetRecord.sha256 -cne [string]$expected.target_record_file_sha256) {
        throw "[mir42-seal-candidate-historical-target-record-binding] $([string]$target.target)"
      }
      if ([string]$versionContract.source_version -cin @('4.3.0','4.3.1')) {
        $historicalReceipt = Get-MIR42HistoricalMaterializerReceiptCustody -Root $root -Target ([string]$target.target) -Row $row
      }
    }
    $returned = [ordered]@{
      target = [string]$target.target
      distribution_version = [string]$target.distribution_version
      archive_sha256 = [string]$target.asset.sha256
      content_sha256 = [string]$target.content_sha256
      entry_count = [int]$target.entry_count
      archive_path = $assetPath
    }
    if ($null -ne $historicalReceipt) {
      $returned.historical_materializer_manifest = $historicalReceipt.descriptor
      $returned.historical_materializer_manifest_path = $historicalReceipt.path
    }
    $rows.Add([pscustomobject]$returned)
  }
  return [pscustomobject][ordered]@{identity=$candidateInput;source=$source;scope=$targetScope;targets=@($rows)}
}

function Assert-MIR42ReceiptBinding {
  param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][string]$Code,[string]$ExpectedTargetStatus='passed')
  $record = $Receipt.record
  if ([string]$record.candidate_manifest.sha256 -cne [string]$Candidate.identity.sha256 -or
      [string]$record.candidate_manifest.record_sha256 -cne [string]$Candidate.identity.record.record_sha256 -or
      [string]$record.source.commit -cne [string]$Candidate.source.commit -or
      [string]$record.source.tree -cne [string]$Candidate.source.tree -or
      [string]$record.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256) {
    throw "[$Code-candidate-binding]"
  }
  $candidateTargets = @($Candidate.targets | ForEach-Object { [string]$_.target })
  $receiptTargets = @($record.targets | ForEach-Object { [string]$_.target })
  if (($receiptTargets -join '|') -cne ($candidateTargets -join '|')) {
    throw "[$Code-target-set]"
  }
  foreach ($candidateTarget in @($Candidate.targets)) {
    $row = @($record.targets | Where-Object { [string]$_.target -ceq [string]$candidateTarget.target })
    if ($row.Count -ne 1 -or [string]$row[0].distribution_version -cne [string]$candidateTarget.distribution_version -or
        [string]$row[0].archive.sha256 -cne [string]$candidateTarget.archive_sha256 -or
        [string]$row[0].archive.content_sha256 -cne [string]$candidateTarget.content_sha256 -or
        [int]$row[0].archive.entry_count -ne [int]$candidateTarget.entry_count -or
        [string]$row[0].status -cne $ExpectedTargetStatus) {
      throw "[$Code-target-binding] $([string]$candidateTarget.target)"
    }
  }
}

function Assert-MIR42JoinedAcceptanceCoverage {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)]$Candidate)
  $expectedCriteria = @($script:MIR42SealReleaseAcceptanceCriteria)
  $candidateTargets = @($Candidate.targets | ForEach-Object { [string]$_.target })
  $requiresNineTargetCriterionRecords = ($candidateTargets -join '|') -ceq ($script:MIR42SealNineTargetCandidates -join '|')
  $rows = @($Receipt.record.release_acceptance)
  $actualCriteria = @($rows | ForEach-Object { [string]$_.criterion })
  if ($rows.Count -ne $expectedCriteria.Count -or ($actualCriteria -join '|') -cne ($expectedCriteria -join '|')) {
    throw '[mir42-seal-qualification-joined-acceptance-missing]'
  }
  foreach ($row in $rows) {
    Assert-MIR42SealPropertyNames -Value $row -Expected @('criterion','status','observed_targets','not_applicable_targets','evidence','limits') -Code 'mir42-seal-qualification-joined-acceptance-shape'
    $observed = @($row.observed_targets | ForEach-Object { [string]$_ })
    $notApplicable = @($row.not_applicable_targets)
    $notApplicableIds = @($notApplicable | ForEach-Object { [string]$_.target })
    foreach ($omission in $notApplicable) {
      Assert-MIR42SealPropertyNames -Value $omission -Expected @('target','reason') -Code 'mir42-seal-qualification-not-applicable-shape'
      if ([string]::IsNullOrWhiteSpace([string]$omission.reason)) {
        throw "[mir42-seal-qualification-not-applicable-binding] $([string]$row.criterion)/$([string]$omission.target)"
      }
    }
    foreach ($evidence in @($row.evidence)) {
      Assert-MIR42SealPropertyNames -Value $evidence -Expected @('path','sha256','record_sha256') -Code 'mir42-seal-qualification-evidence-shape'
      $evidencePath = Resolve-MIR42SealImmutableFile -Path ([string]$evidence.path) -Sha256 ([string]$evidence.sha256) -Code 'mir42-seal-qualification-evidence'
      $evidenceRecord = Read-MIR42SealRecord -Path $evidencePath -Code 'mir42-seal-qualification-evidence'
      if ([string]$evidenceRecord.record.record_sha256 -cne [string]$evidence.record_sha256) { throw '[mir42-seal-qualification-evidence-record-binding]' }
      if ($requiresNineTargetCriterionRecords) {
        $criterionEvidence = Get-MIR42NineTargetCriterionEvidenceRecord -Path $evidencePath -Candidate $Candidate
        $expectedRow = $criterionEvidence.record | Select-Object criterion,status,observed_targets,not_applicable_targets,evidence,limits
        if ([string]$criterionEvidence.record.criterion -cne [string]$row.criterion -or
            (ConvertTo-MIR4BootstrapCanonicalJson -Value $expectedRow) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $row)) {
          throw '[mir42-seal-qualification-evidence-criterion-binding]'
        }
      }
    }
    Assert-MIR42SealPropertyNames -Value $row.limits -Expected @('claim','known_limitations') -Code 'mir42-seal-qualification-limits-shape'
    if ([string]$row.status -cne 'passed' -or $observed.Count -eq 0 -or @($row.evidence).Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$row.limits.claim) -or
        @($observed + $notApplicableIds).Count -ne $candidateTargets.Count -or
        (@($observed + $notApplicableIds | Sort-Object -Unique).Count -ne $candidateTargets.Count) -or
        ((@($observed + $notApplicableIds | Sort-Object { [array]::IndexOf($candidateTargets, [string]$_) }) -join '|') -cne ($candidateTargets -join '|')) -or
        @($row.evidence | Where-Object { [string]$_.sha256 -notmatch '^[A-F0-9]{64}$' -or [string]$_.record_sha256 -notmatch '^[A-F0-9]{64}$' }).Count -ne 0) {
      throw "[mir42-seal-qualification-joined-acceptance-binding] $([string]$row.criterion)"
    }
  }
}

function Get-MIR42ExactQualificationReceipt {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate,$PublishedMaintenanceInputs = $null)
  $scope = Get-MIR42SealCandidateScope -Candidate $Candidate -Code 'mir42-seal-qualification-candidate'
  $contract = Get-MIR42EngineEvidenceBindingContract -Candidate $Candidate -PublishedMaintenance:($null -ne $PublishedMaintenanceInputs)
  $receipt = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-qualification'
  $properties = @('schema','kind','status','reconciliation_scope','source','candidate_manifest','targets',$contract.reconciliation_target_requirement,'cross_target_substitution','factorio_processes','release_qualification','independent_verification','technical_seal','source_freeze_authorized','signing_authorized','tagging_authorized','publication_authorized','nonclaims','record_sha256')
  if ($null -ne $PublishedMaintenanceInputs) { $properties += 'published_maintenance_predecessor' }
  Assert-MIR42SealPropertyNames -Value $receipt.record -Expected $properties -Code 'mir42-seal-evidence-reconciliation-shape'
  if ([int]$receipt.record.schema -ne 1 -or [string]$receipt.record.kind -cne [string]$contract.evidence_kind -or
      [string]$receipt.record.status -cne [string]$contract.evidence_status -or
      -not [bool]$receipt.record.($contract.reconciliation_target_requirement) -or [bool]$receipt.record.cross_target_substitution -or
      [int]$receipt.record.factorio_processes -ne 0 -or
      [string]$receipt.record.release_qualification -cne 'not-performed' -or
      [string]$receipt.record.independent_verification -cne 'not-performed' -or
      [string]$receipt.record.technical_seal -cne 'not-performed' -or
      [bool]$receipt.record.source_freeze_authorized -or [bool]$receipt.record.signing_authorized -or [bool]$receipt.record.tagging_authorized -or
      [bool]$receipt.record.publication_authorized) {
    throw '[mir42-seal-evidence-reconciliation-state]'
  }
  Assert-MIR42ReceiptBinding -Receipt $receipt -Candidate $Candidate -Code 'mir42-seal-qualification' -ExpectedTargetStatus 'reconciled'
  if ($null -ne $PublishedMaintenanceInputs) {
    Assert-MIR42EngineEvidenceMaintenanceCustody -Recorded $receipt.record.published_maintenance_predecessor -Current $PublishedMaintenanceInputs -Code 'mir42-engine-evidence-reconciliation-custody-binding'
    foreach ($row in @($receipt.record.targets)) {
      $input = @($PublishedMaintenanceInputs.targets | Where-Object { [string]$_.target -ceq [string]$row.target })[0]
      if ($row.PSObject.Properties.Name -notcontains 'published_maintenance_predecessor') {
        throw "[mir42-engine-evidence-reconciliation-row-custody-missing] $([string]$row.target)"
      }
      Assert-MIR42EngineEvidenceMaintenanceCustody -Recorded $row.published_maintenance_predecessor -Current $input -Code ('mir42-engine-evidence-reconciliation-row-custody-binding-' + [string]$row.target)
      if ([string]$row.predecessor.version -cne [string]$input.version -or
          [string]$row.predecessor.archive.path -cne [IO.Path]::GetFileName([string]$input.path) -or
          [string]$row.predecessor.archive.sha256 -cne [string]$input.sha256 -or
          [int64]$row.predecessor.archive.bytes -ne [int64]$input.bytes -or
          [string]$row.predecessor.archive.content_sha256 -cne [string]$input.content_sha256 -or
          [int]$row.predecessor.archive.entry_count -ne [int]$input.entry_count) {
        throw "[mir42-engine-evidence-reconciliation-predecessor-binding] $([string]$row.target)"
      }
    }
  }
  return $receipt
}

function Assert-MIR42FreshEngineLoads {
  param([Parameter(Mandatory)]$Target,[Parameter(Mandatory)]$CandidateTarget,[Parameter(Mandatory)]$Execution)
  $targetId = [string]$Target.target
  $expectedFactorioVersion = [regex]::Match([string]$Execution.version, '^[0-9]+[.][0-9]+[.][0-9]+').Value
  if ([string]::IsNullOrWhiteSpace($expectedFactorioVersion)) { throw "[mir42-seal-real-engine-version-shape] $targetId" }
  [string[]]$expectedScenarios = if ($targetId -ceq 'f210') { @('package-zip-base','package-zip-space-age') } else { @('package-zip-base') }
  $freshLoads = @($Execution.fresh_loads)
  if ($freshLoads.Count -ne $expectedScenarios.Count -or
      ((@($freshLoads | ForEach-Object { [string]$_.scenario }) -join '|') -cne ($expectedScenarios -join '|'))) {
    throw "[mir42-seal-real-engine-fresh-load-set] $targetId"
  }
  foreach ($fresh in $freshLoads) {
    Assert-MIR42SealPropertyNames -Value $fresh -Expected @('scenario','receipt','log','stdout','stderr') -Code 'mir42-seal-real-engine-fresh-load-shape'
    foreach ($field in @('receipt','log','stdout','stderr')) {
      Assert-MIR42SealPropertyNames -Value $fresh.$field -Expected @('path','sha256') -Code "mir42-seal-real-engine-fresh-load-$field-shape"
      $null = Resolve-MIR42SealImmutableFile -Path ([string]$fresh.$field.path) -Sha256 ([string]$fresh.$field.sha256) -Code "mir42-seal-real-engine-fresh-load-$field"
    }
    try { $summary = Get-Content -Raw -LiteralPath ([string]$fresh.receipt.path) | ConvertFrom-Json -Depth 100 -DateKind String }
    catch { throw "[mir42-seal-real-engine-fresh-load-receipt-json] $targetId/$([string]$fresh.scenario)" }
    if ($targetId -in $script:MIR42SealHistoricalTargets) {
      $required = @('exact-engine','exact-candidate','fresh-save-created','exact-mod-loaded','map-created','healthy-log')
      if ([int]$summary.schema -ne 1 -or [string]$summary.kind -cne 'MIR42HistoricalFreshLoadV1' -or
          [string]$summary.status -cne 'passed' -or [string]$summary.target -cne $targetId -or
          [string]$summary.source_commit -cne [string]$CandidateTarget.source.commit -or
          [string]$summary.factorio_line -cne ([string]$Target.target_id -replace '^factorio-', '') -or
          [string]$summary.engine.path -cne [string]$Execution.executable_path -or
          [string]$summary.engine.sha256 -cne [string]$Execution.executable_sha256 -or
          [string]$summary.candidate.sha256 -cne [string]$Target.archive.sha256 -or
          [string]$summary.candidate.version -cne [string]$Target.distribution_version -or
          [string]$summary.staged_candidate_sha256 -cne [string]$Target.archive.sha256 -or
          [string]$summary.log.sha256 -cne [string]$fresh.log.sha256 -or
          [string]$summary.log.path -cne [string]$fresh.log.path -or
          @($summary.assertions).Count -ne $required.Count -or
          (@($summary.assertions | ForEach-Object { [string]$_ }) -join '|') -cne ($required -join '|') -or
          -not (Test-MIR4BootstrapRecordHash -Record $summary)) {
        throw "[mir42-seal-real-engine-fresh-load-binding] $targetId/$([string]$fresh.scenario)"
      }
      $null = Resolve-MIR42SealImmutableFile -Path ([string]$summary.save.path) -Sha256 ([string]$summary.save.sha256) -Code 'mir42-seal-historical-fresh-save'
      $null = Resolve-MIR42SealImmutableFile -Path ([string]$summary.candidate.path) -Sha256 ([string]$summary.candidate.sha256) -Code 'mir42-seal-historical-fresh-candidate'
    } else {
      $scenarioRows = @($summary.scenarios)
      if ([int]$summary.schema -ne 2 -or
        [string]$summary.status -cne 'passed' -or
        [string]$summary.git_commit -cne [string]$CandidateTarget.source.commit -or
        [string]$summary.validation_package_sha256 -cne [string]$Target.archive.sha256 -or
        [string]$summary.validation_package_content_sha256 -cne [string]$Target.archive.content_sha256 -or
        [string]$summary.factorio_binary_version -cne $expectedFactorioVersion -or
        @($summary.expected_scenarios).Count -ne 1 -or
        [string]$summary.expected_scenarios[0] -cne [string]$fresh.scenario -or
        $scenarioRows.Count -ne 1 -or
        [string]$scenarioRows[0].name -cne [string]$fresh.scenario -or
        [string]$scenarioRows[0].status -cne 'passed' -or
        [int]$scenarioRows[0].assertions_executed -le 0) {
        throw "[mir42-seal-real-engine-fresh-load-binding] $targetId/$([string]$fresh.scenario)"
      }
    }
    $logText = Get-Content -Raw -LiteralPath ([string]$fresh.log.path)
    $logModVersion = [string]$Target.distribution_version
    if ($targetId -in $script:MIR42SealHistoricalTargets) {
      if ($logModVersion -notmatch '^4[.](2|3)[.]([0-9]+)$') { throw "[mir42-seal-historical-distribution-version] $targetId" }
      $logModVersion = '4.' + $Matches[1] + '.' + [int]$Matches[2]
    }
    if (-not $logText.Contains("Loading mod more-infinite-research $logModVersion ") -or
        -not $logText.Contains('Factorio initialised') -or -not $logText.Contains('Creating new map')) {
      throw "[mir42-seal-real-engine-fresh-load-log-marker] $targetId/$([string]$fresh.scenario)"
    }
  }
}

function Assert-MIR42ExactEngineAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Target,[Parameter(Mandatory)]$Execution,[switch]$PublishedMaintenance)
  $targetId = [string]$Target.target
  $binary = Get-Item -LiteralPath ([string]$Execution.executable_path)
  $productVersion = [string]$binary.VersionInfo.ProductVersion
  if ($productVersion -match '^([0-9]+[.][0-9]+[.][0-9]+)') { $productVersion = [string]$Matches[1] }
  $observed = [pscustomobject][ordered]@{
    version = $productVersion
    file_version = [string]$binary.VersionInfo.FileVersion
    binary_sha256 = (Get-FileHash -LiteralPath $binary.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
  }
  if ([string]$Execution.executable_sha256 -cne [string]$observed.binary_sha256 -or
      [string]$Execution.version -cne [string]$observed.file_version) {
    throw "[mir42-seal-engine-local-identity-drift] $targetId"
  }
  if ($PublishedMaintenance) {
    Assert-MIR421NativeEngineIdentity -RepoRoot $RepoRoot -Target $targetId -Observed ([pscustomobject]@{
      product_version=$observed.version;file_version=$observed.file_version;sha256=$observed.binary_sha256
    })
  } elseif ($targetId -ceq 'f210') {
    $admission = Get-MIR4F210CurrentEngineCapHarnessAdmissionV3 -RepoRoot $RepoRoot
    if ([string]$admission.engine.binary.sha256 -cne [string]$observed.binary_sha256 -or
        [string]$admission.engine.file_version -cne [string]$observed.file_version) {
      throw '[mir42-seal-f210-engine-authority-drift]'
    }
  } elseif (-not (Test-MIR4FixedFactorioEngineIdentity -Target $targetId -ObservedIdentity $observed -RepoRoot $RepoRoot)) {
    throw "[mir42-seal-fixed-engine-authority-drift] $targetId"
  }
}

function Get-MIR42DirectPredecessorAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Reference)
  Assert-MIR42SealPropertyNames -Value $Reference -Expected @('path','sha256','record_sha256') -Code 'mir42-seal-predecessor-authority-reference-shape'
  $authorityPath = Resolve-MIR42SealImmutableFile -Path ([string]$Reference.path) -Sha256 ([string]$Reference.sha256) -Code 'mir42-seal-predecessor-authority-reference'
  $authority = Read-MIR42SealRecord -Path $authorityPath -Code 'mir42-seal-predecessor-authority'
  $record = $authority.record
  if ([string]$record.record_sha256 -cne [string]$Reference.record_sha256) { throw '[mir42-seal-predecessor-authority-reference-binding]' }
  Assert-MIR42SealPropertyNames -Value $record -Expected @('schema','kind','status','public_v410_checksums','targets','release_transition_authority','publication_authorized','record_sha256') -Code 'mir42-seal-predecessor-authority-shape'
  Assert-MIR42SealPropertyNames -Value $record.public_v410_checksums -Expected @('tag','tag_object','tagged_commit','path','sha256','verified_tag_fingerprint','release_asset_id','release_asset_bytes') -Code 'mir42-seal-predecessor-checksums-shape'
  if ([int]$record.schema -ne 1 -or
      [string]$record.kind -cne 'MIR42DirectPredecessorInputsV1' -or
      [string]$record.status -cne 'verified-published-v410-checksum-and-local-custody-private' -or
      [bool]$record.release_transition_authority -or [bool]$record.publication_authorized) {
    throw '[mir42-seal-predecessor-authority-state]'
  }
  $checksumRelative = [string]$record.public_v410_checksums.path
  if ($checksumRelative -cne '.mir/releases/governance/mir4/MIR42-v410-SHA256SUMS.txt') { throw '[mir42-seal-predecessor-checksums-path]' }
  $checksumPath = Resolve-MIR42SealContainedArtifactPath -Root $RepoRoot -RelativePath $checksumRelative -Code 'mir42-seal-predecessor-checksums'
  if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $checksumPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$record.public_v410_checksums.sha256) {
    throw '[mir42-seal-predecessor-checksums-drift]'
  }
  if ([int64]$record.public_v410_checksums.release_asset_id -le 0 -or [int64]$record.public_v410_checksums.release_asset_bytes -ne [int64](Get-Item -LiteralPath $checksumPath).Length) {
    throw '[mir42-seal-predecessor-public-asset-shape]'
  }
  $tag = [string]$record.public_v410_checksums.tag
  $tagObject = (& git -C $RepoRoot rev-parse "${tag}^{object}").Trim()
  $taggedCommit = (& git -C $RepoRoot rev-parse "${tag}^{commit}").Trim()
  $tagVerification = @(& git -C $RepoRoot tag --verify $tag 2>&1)
  if ($LASTEXITCODE -ne 0 -or $tagObject -cne [string]$record.public_v410_checksums.tag_object -or
      $taggedCommit -cne [string]$record.public_v410_checksums.tagged_commit -or
      (($tagVerification -join "`n") -notmatch ('Good "git" signature.*key ' + [regex]::Escape([string]$record.public_v410_checksums.verified_tag_fingerprint)))) {
    throw '[mir42-seal-predecessor-public-tag-binding]'
  }
  Assert-MIR42SealTargetSet -Rows @($record.targets) -Code 'mir42-seal-predecessor-authority'
  foreach ($row in @($record.targets)) {
    Assert-MIR42SealPropertyNames -Value $row -Expected @('target','predecessor','published_checksum_sha256','engine') -Code 'mir42-seal-predecessor-target-shape'
    Assert-MIR42SealPropertyNames -Value $row.predecessor -Expected @('version','path','sha256','bytes') -Code 'mir42-seal-predecessor-input-shape'
    Assert-MIR42SealPropertyNames -Value $row.engine -Expected @('path','file_version','product_version','sha256','channel') -Code 'mir42-seal-predecessor-engine-shape'
    $predecessorPath = Resolve-MIR42SealImmutableFile -Path ([string]$row.predecessor.path) -Sha256 ([string]$row.predecessor.sha256) -Code 'mir42-seal-predecessor-input'
    if ([int64](Get-Item -LiteralPath $predecessorPath).Length -ne [int64]$row.predecessor.bytes -or
        [string]$row.published_checksum_sha256 -cne [string]$row.predecessor.sha256 -or
        ([IO.Path]::GetFileName($predecessorPath) -cne "more-infinite-research_$([string]$row.predecessor.version).zip") -or
        @((Get-Content -LiteralPath $checksumPath | Where-Object { $_ -match ('^' + [regex]::Escape([string]$row.predecessor.sha256) + '\s{2}' + [regex]::Escape([IO.Path]::GetFileName($predecessorPath)) + '$') })).Count -ne 1) {
      throw "[mir42-seal-predecessor-input-binding] $([string]$row.target)"
    }
  }
  return $authority
}

function Assert-MIR42PublishedV410ChecksumAsset {
  param([Parameter(Mandatory)]$Authority,[Parameter(Mandatory)]$RunAsset)
  Assert-MIR42SealPropertyNames -Value $RunAsset -Expected @('release_id','asset_id','digest','bytes','download_verified') -Code 'mir42-seal-predecessor-run-asset-shape'
  $checksums = $Authority.record.public_v410_checksums
  $expectedDigest = 'sha256:' + ([string]$checksums.sha256).ToLowerInvariant()
  if ([int64]$RunAsset.release_id -le 0 -or
      [int64]$RunAsset.asset_id -ne [int64]$checksums.release_asset_id -or
      [int64]$RunAsset.bytes -ne [int64]$checksums.release_asset_bytes -or
      [string]$RunAsset.digest -cne $expectedDigest -or -not [bool]$RunAsset.download_verified) {
    throw '[mir42-seal-predecessor-run-asset-binding]'
  }
  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if ($null -eq $gh) { throw '[mir42-seal-predecessor-public-asset-client-missing]' }
  try {
    $raw = & $gh.Source api ("repos/Julesc013/more-infinite-research/releases/tags/" + [string]$checksums.tag) 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'gh-failed' }
    $release = ($raw -join "`n") | ConvertFrom-Json -Depth 100 -DateKind String
    $asset = @($release.assets | Where-Object { [string]$_.name -ceq 'SHA256SUMS.txt' })
    if ([string]$release.tag_name -cne [string]$checksums.tag -or $asset.Count -ne 1 -or
        [int64]$release.id -ne [int64]$RunAsset.release_id -or [int64]$asset[0].id -ne [int64]$RunAsset.asset_id -or
        [int64]$asset[0].size -ne [int64]$RunAsset.bytes -or [string]$asset[0].digest -cne [string]$RunAsset.digest) {
      throw 'asset-drift'
    }
  } catch { throw '[mir42-seal-predecessor-public-asset-live-binding]' }
}

function Assert-MIR42GovernedPredecessor {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Target,[Parameter(Mandatory)]$Execution,[Parameter(Mandatory)]$AuthorityReference,[Parameter(Mandatory)]$RunAsset,$PublishedMaintenanceInput = $null)
  if ($null -ne $PublishedMaintenanceInput) {
    # Maintenance custody is the independently read-back published CCC00 set.
    # The frozen v4.1 input record retains its original engine and archive paths.
    Assert-MIR42EngineEvidenceMaintenanceExecution -Target ([string]$Target.target) -Execution $Execution -PublishedInput $PublishedMaintenanceInput
    Assert-MIR42ExactEngineAuthority -RepoRoot $RepoRoot -Target $Target -Execution $Execution -PublishedMaintenance
    return
  }
  $authority = Get-MIR42DirectPredecessorAuthority -RepoRoot $RepoRoot -Reference $AuthorityReference
  Assert-MIR42PublishedV410ChecksumAsset -Authority $authority -RunAsset $RunAsset
  $rows = @($authority.record.targets | Where-Object { [string]$_.target -ceq [string]$Target.target })
  $expectedPredecessor = if ($null -ne $PublishedMaintenanceInput) { $PublishedMaintenanceInput } elseif ($rows.Count -eq 1) { $rows[0].predecessor } else { $null }
  if ($null -ne $PublishedMaintenanceInput) {
    Assert-MIR42EngineEvidenceMaintenanceExecution -Target ([string]$Target.target) -Execution $Execution -PublishedInput $PublishedMaintenanceInput
  }
  $authorityPredecessorPath = if ($null -ne $expectedPredecessor) { [IO.Path]::GetFullPath([string]$expectedPredecessor.path) } else { '' }
  $executionPredecessorPath = [IO.Path]::GetFullPath([string]$Execution.predecessor.path)
  $authorityEnginePath = if ($rows.Count -eq 1) { [IO.Path]::GetFullPath([string]$rows[0].engine.path) } else { '' }
  $executionEnginePath = [IO.Path]::GetFullPath([string]$Execution.executable_path)
  $productVersion = [string](Get-Item -LiteralPath $executionEnginePath).VersionInfo.ProductVersion
  if ($productVersion -match '^([0-9]+[.][0-9]+[.][0-9]+)') { $productVersion = [string]$Matches[1] }
  if ($rows.Count -ne 1 -or
      [string]$expectedPredecessor.version -cne [string]$Execution.predecessor.version -or
      -not $authorityPredecessorPath.Equals($executionPredecessorPath,[StringComparison]::OrdinalIgnoreCase) -or
      [string]$expectedPredecessor.sha256 -cne [string]$Execution.predecessor.sha256 -or
      -not $authorityEnginePath.Equals($executionEnginePath,[StringComparison]::OrdinalIgnoreCase) -or
      [string]$rows[0].engine.file_version -cne [string]$Execution.version -or
      [string]$rows[0].engine.product_version -cne $productVersion -or
      [string]$rows[0].engine.sha256 -cne [string]$Execution.executable_sha256) {
    throw "[mir42-seal-predecessor-execution-binding] $([string]$Target.target)"
  }
}

function Get-MIR42HistoricalTerminalAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Target,[switch]$PredecessorIdentityOnly)
  if ($Target -notin $script:MIR42SealHistoricalTargets) { throw "[mir42-seal-historical-target] $Target" }
  $identity = Get-MIR42ReleaseTargetIdentity -RepoRoot $RepoRoot -Target $Target
  if ($identity.PSObject.Properties.Name -notcontains 'target_record_path') { throw "[mir42-seal-historical-target-record-missing] $Target" }
  $targetRecordPath = Resolve-MIR42SealContainedArtifactPath -Root $RepoRoot -RelativePath ([string]$identity.target_record_path) -Code 'mir42-seal-historical-target-record'
  $targetRecord = Read-MIR42SealRecord -Path $targetRecordPath -Code 'mir42-seal-historical-target-record'
  $record = $targetRecord.record
  if ([string]$targetRecord.sha256 -cne [string]$identity.target_record_file_sha256 -or
      [string]$record.record_sha256 -cne [string]$identity.target_record_record_sha256 -or
      [int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42HistoricalPlaytestTargetV1' -or
      [string]$record.target -cne $Target -or [string]$record.maturity -cne 'private-historical-playtest' -or
      [string]$record.base_materializer_target -cne 'f100' -or [string]$record.factorio_line -cne ([string]$identity.target_id -replace '^factorio-', '') -or
      [string]$record.distribution_version -cne [string]$identity.distribution_version -or
      [bool]$record.public_output_authorized -or [bool]$record.publication_authorized) {
    throw "[mir42-seal-historical-target-record-state] $Target"
  }
  $sealRelative = '.mir/releases/terminal/seals/' + [string]$record.predecessor.version + '.json'
  $sealPath = Resolve-MIR42SealContainedArtifactPath -Root $RepoRoot -RelativePath $sealRelative -Code 'mir42-seal-historical-terminal-seal'
  $seal = Read-MIR42SealRecord -Path $sealPath -Code 'mir42-seal-historical-terminal-seal'
  if ([int]$seal.record.schema -ne 1 -or [string]$seal.record.kind -cne 'Mir3TerminalTargetSealV1' -or
      [string]$seal.record.status -cne 'sealed' -or [string]$seal.record.release -cne [string]$record.predecessor.version -or
      [string]$seal.record.target -cne [string]$record.factorio_line -or [string]$seal.record.archive_sha256 -cne [string]$record.predecessor.sha256 -or
      [string]$seal.record.engine.version -cne [string]$record.engine.version -or [string]$seal.record.engine.binary_sha256 -cne [string]$record.engine.sha256) {
    throw "[mir42-seal-historical-terminal-seal-binding] $Target"
  }
  $predecessorPath = ''
  if (-not $PredecessorIdentityOnly) {
    $predecessorPath = Resolve-MIR42SealContainedArtifactPath -Root $RepoRoot -RelativePath ([string]$record.predecessor.archive) -Code 'mir42-seal-historical-predecessor'
    $inventory = Get-MIR4ArchiveInventory -Path $predecessorPath
    if ([string]$inventory.archive_sha256 -cne [string]$seal.record.archive_sha256 -or
        [int64]$inventory.bytes -ne [int64]$seal.record.bytes -or [string]$inventory.content_sha256 -cne [string]$seal.record.content_sha256 -or
        [int]$inventory.entry_count -ne [int]$seal.record.entries) {
      throw "[mir42-seal-historical-predecessor-binding] $Target"
    }
  }
  return [pscustomobject][ordered]@{identity=$identity;target_record=$targetRecord;terminal_seal=$seal;predecessor_path=$predecessorPath}
}

function Assert-MIR42HistoricalTerminalExecution {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Target,
    [Parameter(Mandatory)]$Execution,
    [Parameter(Mandatory)]$HistoricalAuthorities,
    $PublishedMaintenanceInput = $null
  )
  $targetId = [string]$Target.target
  $expected = Get-MIR42HistoricalTerminalAuthority -RepoRoot $RepoRoot -Target $targetId -PredecessorIdentityOnly:($null -ne $PublishedMaintenanceInput)
  $rows = @($HistoricalAuthorities | Where-Object { [string]$_.target -ceq $targetId })
  if ($rows.Count -ne 1) { throw "[mir42-seal-historical-authority-cardinality] $targetId" }
  Assert-MIR42SealPropertyNames -Value $rows[0] -Expected @('target','authority') -Code 'mir42-seal-historical-authority-shape'
  $authority = $rows[0].authority
  Assert-MIR42SealPropertyNames -Value $authority -Expected @('target_record','terminal_seal','engine','predecessor') -Code 'mir42-seal-historical-authority-fields'
  Assert-MIR42SealPropertyNames -Value $authority.target_record -Expected @('path','sha256','record_sha256') -Code 'mir42-seal-historical-authority-target-record-shape'
  Assert-MIR42SealPropertyNames -Value $authority.terminal_seal -Expected @('path','sha256','record_sha256','target','release') -Code 'mir42-seal-historical-authority-terminal-seal-shape'
  Assert-MIR42SealPropertyNames -Value $authority.engine -Expected @('path','version','sha256') -Code 'mir42-seal-historical-authority-engine-shape'
  Assert-MIR42SealPropertyNames -Value $authority.predecessor -Expected @('path','version','sha256','bytes','content_sha256','entry_count') -Code 'mir42-seal-historical-authority-predecessor-shape'
  $expectedTargetRecord = $expected.target_record.record
  $expectedTerminalSeal = $expected.terminal_seal.record
  if ([string]$authority.target_record.path -cne [string]$expected.identity.target_record_path -or
      [string]$authority.target_record.sha256 -cne [string]$expected.target_record.sha256 -or
      [string]$authority.target_record.record_sha256 -cne [string]$expectedTargetRecord.record_sha256 -or
      [string]$authority.terminal_seal.path -cne ('.mir/releases/terminal/seals/' + [string]$expectedTargetRecord.predecessor.version + '.json') -or
      [string]$authority.terminal_seal.sha256 -cne [string]$expected.terminal_seal.sha256 -or
      [string]$authority.terminal_seal.record_sha256 -cne [string]$expectedTerminalSeal.record_sha256 -or
      [string]$authority.terminal_seal.target -cne [string]$expectedTargetRecord.factorio_line -or
      [string]$authority.terminal_seal.release -cne [string]$expectedTargetRecord.predecessor.version -or
      -not ([IO.Path]::GetFullPath([string]$authority.engine.path)).Equals([IO.Path]::GetFullPath([string]$expectedTargetRecord.engine.path),[StringComparison]::OrdinalIgnoreCase) -or
      [string]$authority.engine.version -cne [string]$expectedTargetRecord.engine.version -or [string]$authority.engine.sha256 -cne [string]$expectedTargetRecord.engine.sha256 -or
      [string]$authority.predecessor.path -cne [string]$expectedTargetRecord.predecessor.archive -or [string]$authority.predecessor.version -cne [string]$expectedTargetRecord.predecessor.version -or
      [string]$authority.predecessor.sha256 -cne [string]$expectedTerminalSeal.archive_sha256 -or [int64]$authority.predecessor.bytes -ne [int64]$expectedTerminalSeal.bytes -or
      [string]$authority.predecessor.content_sha256 -cne [string]$expectedTerminalSeal.content_sha256 -or [int]$authority.predecessor.entry_count -ne [int]$expectedTerminalSeal.entries) {
    throw "[mir42-seal-historical-authority-binding] $targetId"
  }
  $executionProperties = @('executable_path','executable_sha256','version','predecessor','harness_receipt','harness_exit_code','logs','fresh_loads','fresh_exact_load','predecessor_upgrade','reload_count','historical_terminal_authority')
  if ($null -ne $PublishedMaintenanceInput) { $executionProperties += 'published_maintenance_predecessor' }
  Assert-MIR42SealPropertyNames -Value $Execution -Expected $executionProperties -Code 'mir42-seal-historical-execution-shape'
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $Execution.historical_terminal_authority) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $authority)) {
    throw "[mir42-seal-historical-execution-authority-binding] $targetId"
  }
  $enginePath = Resolve-MIR42SealImmutableFile -Path ([string]$Execution.executable_path) -Sha256 ([string]$Execution.executable_sha256) -Code 'mir42-seal-historical-engine'
  $predecessorPath = Resolve-MIR42SealImmutableFile -Path ([string]$Execution.predecessor.path) -Sha256 ([string]$Execution.predecessor.sha256) -Code 'mir42-seal-historical-predecessor'
  $expectedPredecessorPath = $expected.predecessor_path
  $expectedPredecessorSha = [string]$expectedTerminalSeal.archive_sha256
  $expectedPredecessorVersion = [string]$expectedTargetRecord.predecessor.version
  if ($null -ne $PublishedMaintenanceInput) {
    Assert-MIR42EngineEvidenceMaintenanceExecution -Target $targetId -Execution $Execution -PublishedInput $PublishedMaintenanceInput
    $expectedPredecessorPath = [IO.Path]::GetFullPath([string]$PublishedMaintenanceInput.path)
    $expectedPredecessorSha = [string]$PublishedMaintenanceInput.sha256
    $expectedPredecessorVersion = [string]$PublishedMaintenanceInput.version
  }
  if (($null -eq $PublishedMaintenanceInput -and -not $enginePath.Equals([IO.Path]::GetFullPath([string]$expectedTargetRecord.engine.path),[StringComparison]::OrdinalIgnoreCase)) -or
      [string]$Execution.executable_sha256 -cne [string]$expectedTargetRecord.engine.sha256 -or [string]$Execution.version -cne [string]$expectedTargetRecord.engine.version -or
      -not $predecessorPath.Equals($expectedPredecessorPath,[StringComparison]::OrdinalIgnoreCase) -or
      [string]$Execution.predecessor.sha256 -cne $expectedPredecessorSha -or [string]$Execution.predecessor.version -cne $expectedPredecessorVersion) {
    throw "[mir42-seal-historical-execution-binding] $targetId"
  }
}

function Get-MIR42BoundEngineRun {
  param([Parameter(Mandatory)]$Reference,[Parameter(Mandatory)]$Candidate,$PublishedMaintenanceInputs = $null)
  Assert-MIR42SealPropertyNames -Value $Reference -Expected @('path','sha256','record_sha256') -Code 'mir42-seal-engine-run-reference-shape'
  $runPath = Resolve-MIR42SealImmutableFile -Path ([string]$Reference.path) -Sha256 ([string]$Reference.sha256) -Code 'mir42-seal-engine-run-reference'
  $run = Read-MIR42SealRecord -Path $runPath -Code 'mir42-seal-engine-run'
  if ([string]$run.record.record_sha256 -cne [string]$Reference.record_sha256) { throw '[mir42-seal-engine-run-reference-binding]' }
  if ([string]$run.record.kind -ceq 'MIR42NineTargetMaintenanceIndividualEngineRunV1') {
    if ($null -eq $PublishedMaintenanceInputs) { throw '[mir42-individual-engine-run-maintenance-required]' }
    return Get-MIR42BoundIndividualEngineRun -Reference $Reference -Candidate $Candidate -PublishedMaintenanceInputs $PublishedMaintenanceInputs
  }
  $scope = Get-MIR42SealCandidateScope -Candidate $Candidate -Code 'mir42-seal-engine-run-candidate'
  $contract = Get-MIR42EngineEvidenceBindingContract -Candidate $Candidate -PublishedMaintenance:($null -ne $PublishedMaintenanceInputs)
  $runProperties = @('schema','kind','status','source','candidate_manifest','predecessor_authority','public_v410_checksum_asset','runner','harness','targets','factorio_processes','release_qualification','publication_authorized','record_sha256')
  $historicalProperty = if ($null -ne $PublishedMaintenanceInputs) { 'historical_target_authorities' } else { 'historical_terminal_predecessors' }
  if ($scope -ceq 'nine-target') { $runProperties += @('historical_upgrade_harness',$historicalProperty) }
  if ($null -ne $PublishedMaintenanceInputs) { $runProperties += 'published_maintenance_predecessor' }
  Assert-MIR42SealPropertyNames -Value $run.record -Expected $runProperties -Code 'mir42-seal-engine-run-shape'
  if ([int]$run.record.schema -ne 1 -or
      [string]$run.record.kind -cne [string]$contract.engine_run_kind -or
      [string]$run.record.status -cne [string]$contract.engine_run_status -or
      [string]$run.record.source.commit -cne [string]$Candidate.source.commit -or
      [string]$run.record.source.tree -cne [string]$Candidate.source.tree -or
      [int]$run.record.factorio_processes -lt 9 -or
      [string]$run.record.release_qualification -cne 'not-performed' -or
      [bool]$run.record.publication_authorized) {
    throw '[mir42-seal-engine-run-state]'
  }
  foreach ($field in @('candidate_manifest','runner','harness')) {
    $expected = if ($field -eq 'candidate_manifest') { @('path','sha256','record_sha256') } else { @('path','sha256') }
    Assert-MIR42SealPropertyNames -Value $run.record.$field -Expected $expected -Code "mir42-seal-engine-run-$field-shape"
    $path = Resolve-MIR42SealImmutableFile -Path ([string]$run.record.$field.path) -Sha256 ([string]$run.record.$field.sha256) -Code "mir42-seal-engine-run-$field"
    if ($field -eq 'candidate_manifest') {
      $manifest = Read-MIR42SealRecord -Path $path -Code 'mir42-seal-engine-run-candidate-manifest'
      if ([string]$manifest.sha256 -cne [string]$Candidate.identity.sha256 -or
          [string]$manifest.record.record_sha256 -cne [string]$Candidate.identity.record.record_sha256 -or
          [string]$manifest.record.record_sha256 -cne [string]$run.record.candidate_manifest.record_sha256) {
        throw '[mir42-seal-engine-run-candidate-manifest-binding]'
      }
    } elseif ($field -eq 'runner' -and (Get-Content -Raw -LiteralPath $path) -notmatch 'Test-MIRUpgrade[.]ps1') {
      throw '[mir42-seal-engine-run-runner-content]'
    } elseif ($field -eq 'harness' -and (Get-Content -Raw -LiteralPath $path) -notmatch 'upgraded-save-second-reload-passed') {
      throw '[mir42-seal-engine-run-harness-content]'
    }
  }
  Assert-MIR42SealCandidateScopeMatch -Rows @($run.record.targets) -Candidate $Candidate -Code 'mir42-seal-engine-run'
  if ($null -ne $PublishedMaintenanceInputs) {
    Assert-MIR42EngineEvidenceMaintenanceCustody -Recorded $run.record.published_maintenance_predecessor -Current $PublishedMaintenanceInputs -Code 'mir42-engine-evidence-run-custody-binding'
  }
  if ($scope -ceq 'nine-target') {
    Assert-MIR42SealPropertyNames -Value $run.record.historical_upgrade_harness -Expected @('fixture_path','fixture_sha256','control_path','control_sha256','upgrade_harness_path','upgrade_harness_sha256') -Code 'mir42-seal-engine-run-historical-harness-shape'
    foreach ($file in @(
      [pscustomobject]@{path=$run.record.historical_upgrade_harness.fixture_path;sha256=$run.record.historical_upgrade_harness.fixture_sha256},
      [pscustomobject]@{path=$run.record.historical_upgrade_harness.control_path;sha256=$run.record.historical_upgrade_harness.control_sha256},
      [pscustomobject]@{path=$run.record.historical_upgrade_harness.upgrade_harness_path;sha256=$run.record.historical_upgrade_harness.upgrade_harness_sha256}
    )) {
      $null = Resolve-MIR42SealImmutableFile -Path ([string]$file.path) -Sha256 ([string]$file.sha256) -Code 'mir42-seal-engine-run-historical-harness'
    }
    $historicalTargets = @($run.record.$historicalProperty | ForEach-Object { [string]$_.target })
    if ($historicalTargets.Count -ne $script:MIR42SealHistoricalTargets.Count -or ($historicalTargets -join '|') -cne ($script:MIR42SealHistoricalTargets -join '|')) {
      throw '[mir42-seal-engine-run-historical-target-set]'
    }
    foreach ($historical in @($run.record.$historicalProperty)) {
      Assert-MIR42SealPropertyNames -Value $historical -Expected @('target','authority') -Code 'mir42-seal-engine-run-historical-authority-shape'
    }
  }
  foreach ($candidateTarget in @($Candidate.targets)) {
    $row = @($run.record.targets | Where-Object { [string]$_.target -ceq [string]$candidateTarget.target })
    if ($row.Count -ne 1) { throw "[mir42-seal-engine-run-target-cardinality] $([string]$candidateTarget.target)" }
    Assert-MIR42SealPropertyNames -Value $row[0] -Expected @('target','status','archive','engine_execution') -Code 'mir42-seal-engine-run-target-shape'
    Assert-MIR42SealPropertyNames -Value $row[0].archive -Expected @('path','sha256') -Code 'mir42-seal-engine-run-archive-shape'
    $archivePath = Resolve-MIR42SealImmutableFile -Path ([string]$row[0].archive.path) -Sha256 ([string]$row[0].archive.sha256) -Code 'mir42-seal-engine-run-archive'
    $runRoot = [IO.Path]::GetFullPath((Split-Path -Parent $run.path)).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    # Engine actors must select the exact archive that already lives in their
    # declared flat library. A byte-identical per-run copy or hard-link is not
    # an additional authority and must not be accepted as native evidence.
    if ([string]$row[0].status -cne 'passed' -or
        [IO.Path]::GetFileName($archivePath) -cne [IO.Path]::GetFileName([string]$candidateTarget.archive_path) -or
        $archivePath.StartsWith($runRoot,[StringComparison]::OrdinalIgnoreCase) -or
        [string]$row[0].archive.sha256 -cne [string]$candidateTarget.archive_sha256) {
      throw "[mir42-seal-engine-run-target-binding] $([string]$candidateTarget.target)"
    }
    if ($null -ne $PublishedMaintenanceInputs) {
      $input = @($PublishedMaintenanceInputs.targets | Where-Object { [string]$_.target -ceq [string]$candidateTarget.target })[0]
      Assert-MIR42EngineEvidenceMaintenanceExecution -Target ([string]$candidateTarget.target) -Execution $row[0].engine_execution -PublishedInput $input
    }
  }
  return $run
}

function Assert-MIR42IndividualNativeCandidateSelection {
  param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)][string]$ReceiptPath,[Parameter(Mandatory)]$CandidateTarget)
  if ($Receipt -isnot [Collections.IDictionary] -or -not $Receipt.Contains('library_activation') -or
      $Receipt.library_activation -isnot [Collections.IDictionary]) {
    throw '[mir42-individual-engine-run-library-activation]'
  }
  $activation = $Receipt.library_activation
  foreach ($field in @('status','dependency_payload_bytes_copied','archive_links_created','archive_extractions','selected')) {
    if (-not $activation.Contains($field)) { throw '[mir42-individual-engine-run-library-activation]' }
  }
  if ([string]$activation.status -cne 'restored-direct-library-controls' -or
      [int64]$activation.dependency_payload_bytes_copied -ne 0 -or [int64]$activation.archive_links_created -ne 0 -or
      [int64]$activation.archive_extractions -ne 0 -or $activation.selected -isnot [array]) {
    throw '[mir42-individual-engine-run-library-activation]'
  }
  $selected = @($activation.selected | Where-Object { $_ -is [Collections.IDictionary] -and [string]$_['name'] -ceq 'more-infinite-research' })
  if ($selected.Count -ne 1) { throw '[mir42-individual-engine-run-native-candidate-selection]' }
  $native = $selected[0]
  foreach ($field in @('name','version','path','builtin','identity','sha256','bytes')) {
    if (-not $native.Contains($field)) { throw '[mir42-individual-engine-run-native-candidate-selection]' }
  }
  if ($native.builtin -isnot [bool] -or [bool]$native.builtin -or [string]$native.version -cne [string]$CandidateTarget.distribution_version -or
      [string]$native.sha256 -cne [string]$CandidateTarget.archive_sha256 -or [int64]$native.bytes -le 0) {
    throw '[mir42-individual-engine-run-native-candidate-selection]'
  }
  $nativePath = Resolve-MIR42SealImmutableFile -Path ([string]$native.path) -Sha256 ([string]$native.sha256) -Code 'mir42-individual-engine-run-native-candidate'
  if ([int64](Get-Item -LiteralPath $nativePath).Length -ne [int64]$native.bytes -or
      [IO.Path]::GetFileName($nativePath) -cne ('more-infinite-research_' + [string]$CandidateTarget.distribution_version + '.zip')) {
    throw '[mir42-individual-engine-run-native-candidate-selection]'
  }
  $receiptRoot = (Split-Path -Parent $ReceiptPath).TrimEnd('\','/')
  $nativeFull = [IO.Path]::GetFullPath($nativePath)
  $rootPrefix = $receiptRoot + [IO.Path]::DirectorySeparatorChar
  if ($nativeFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-individual-engine-run-native-candidate-run-root]' }
  $candidatePath = Resolve-MIR42SealImmutableFile -Path ([string]$CandidateTarget.archive_path) -Sha256 ([string]$CandidateTarget.archive_sha256) -Code 'mir42-individual-engine-run-candidate-authority'
  if ($nativeFull.Equals($candidatePath, [StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-individual-engine-run-native-candidate-authority-path]' }
  if (-not (Get-Command Get-MIRImmutableInputFileIdentity -ErrorAction SilentlyContinue)) {
    . (Join-Path $mir42SealRepoRoot 'tools/lib/validation/ImmutableInputStaging.ps1')
  }
  $nativeIdentity = Get-MIRImmutableInputFileIdentity -Path $nativePath
  $candidateIdentity = Get-MIRImmutableInputFileIdentity -Path $candidatePath
  if ([string]$native.identity -cne [string]$nativeIdentity) { throw '[mir42-individual-engine-run-native-candidate-identity]' }
  if ($nativeIdentity -ceq $candidateIdentity) {
    throw '[mir42-individual-engine-run-native-candidate-authority-link]'
  }
  return [pscustomobject][ordered]@{path=$nativePath;sha256=[string]$native.sha256;bytes=[int64]$native.bytes;identity=[string]$native.identity}
}

function Assert-MIR42IndividualResourceLedgers {
  param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)][string]$ReceiptPath)
  if ($Receipt -isnot [Collections.IDictionary] -or -not $Receipt.Contains('resource_ledgers') -or $Receipt.resource_ledgers -isnot [array] -or
      @($Receipt.resource_ledgers).Count -ne [int]$Receipt.factorio_processes) {
    throw '[mir42-individual-engine-run-resource-ledger-set]'
  }
  $root = Split-Path -Parent $ReceiptPath
  $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($ledger in @($Receipt.resource_ledgers)) {
    if ($ledger -isnot [Collections.IDictionary]) { throw '[mir42-individual-engine-run-resource-ledger-shape]' }
    foreach ($field in @('filename','sha256','exit_code','completion_predicate_observed','peak_working_set_bytes','duration_seconds')) {
      if (-not $ledger.Contains($field)) { throw '[mir42-individual-engine-run-resource-ledger-shape]' }
    }
    $name = [string]$ledger.filename
    if ($name -cne [IO.Path]::GetFileName($name) -or -not $seen.Add($name) -or [string]$ledger.sha256 -notmatch '^[A-F0-9]{64}$' -or
        $ledger.completion_predicate_observed -isnot [bool] -or [int64]$ledger.peak_working_set_bytes -lt 0 -or [double]$ledger.duration_seconds -lt 0) {
      throw '[mir42-individual-engine-run-resource-ledger-shape]'
    }
    $path = Resolve-MIR42SealImmutableFile -Path (Join-Path $root $name) -Sha256 ([string]$ledger.sha256) -Code 'mir42-individual-engine-run-resource-ledger'
    try { $events = @(Get-Content -LiteralPath $path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable -Depth 30 -DateKind String }) }
    catch { throw '[mir42-individual-engine-run-resource-ledger-json]' }
    $interrupted = $false
    foreach ($event in $events) {
      if ($event -isnot [Collections.IDictionary] -or [string]$event['phase'] -ceq 'interrupted') { $interrupted = $true; break }
      if ($event.Contains('timed_out') -and ($event['timed_out'] -isnot [bool] -or [bool]$event['timed_out'])) { $interrupted = $true; break }
    }
    if ($events.Count -eq 0 -or $interrupted) {
      throw '[mir42-individual-engine-run-resource-ledger-interrupted]'
    }
    $terminal = $events[$events.Count - 1]
    if ($terminal -isnot [Collections.IDictionary] -or [string]$terminal.phase -cne 'completed' -or
        -not $terminal.Contains('exit_code') -or -not $terminal.Contains('completion_predicate_observed') -or
        [int]$terminal.exit_code -ne [int]$ledger.exit_code -or $terminal.completion_predicate_observed -isnot [bool] -or
        [bool]$terminal.completion_predicate_observed -ne [bool]$ledger.completion_predicate_observed -or
        ([int]$terminal.exit_code -ne 0 -and -not [bool]$terminal.completion_predicate_observed) -or
        -not $terminal.Contains('peak_working_set_bytes') -or [int64]$terminal.peak_working_set_bytes -ne [int64]$ledger.peak_working_set_bytes) {
      throw '[mir42-individual-engine-run-resource-ledger-terminal]'
    }
  }
}

function Assert-MIR42IndividualUpgradeReceipt {
  param(
    [Parameter(Mandatory)]$ReceiptReference,
    [Parameter(Mandatory)]$CandidateTarget,
    [Parameter(Mandatory)]$PublishedInput,
    [Parameter(Mandatory)]$PublishedMaintenanceInputs,
    [Parameter(Mandatory)]$Engine,
    [Parameter(Mandatory)][int]$HarnessExitCode,
    [Parameter(Mandatory)]$Candidate
  )
  Assert-MIR42SealPropertyNames -Value $ReceiptReference -Expected @('path','sha256') -Code 'mir42-individual-engine-run-receipt-shape'
  Assert-MIR42SealPropertyNames -Value $Engine -Expected @('path','sha256','version') -Code 'mir42-individual-engine-run-engine-shape'
  if ($HarnessExitCode -ne 0) { throw '[mir42-individual-engine-run-harness-exit]' }
  if (-not (Get-Command Assert-MIR423NativeUpgradeProof -ErrorAction SilentlyContinue)) {
    . (Join-Path $mir42SealRepoRoot 'tools/mir/application/release/readiness/MIR42ReleaseAssets.ps1')
  }
  $receiptPath = Resolve-MIR42SealImmutableFile -Path ([string]$ReceiptReference.path) -Sha256 ([string]$ReceiptReference.sha256) -Code 'mir42-individual-engine-run-receipt'
  try { $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -AsHashtable -Depth 100 -DateKind String }
  catch { throw '[mir42-individual-engine-run-receipt-json]' }
  if ([int]$receipt.schema -ne 3 -or [string]$receipt.status -cne 'passed' -or
      [string]$receipt.git_commit -cne [string]$Candidate.source.commit -or
      [string]$receipt.factorio_binary_sha256 -cne [string]$Engine.sha256 -or
      [int]$receipt.factorio_processes -lt 4) {
    throw '[mir42-individual-engine-run-receipt-binding]'
  }
  $enginePath = Resolve-MIR42SealImmutableFile -Path ([string]$Engine.path) -Sha256 ([string]$Engine.sha256) -Code 'mir42-individual-engine-run-engine'
  $productVersion = [string](Get-Item -LiteralPath $enginePath).VersionInfo.ProductVersion
  if ($productVersion -match '^([0-9]+[.][0-9]+[.][0-9]+)') { $productVersion = [string]$Matches[1] }
  $fileVersion = [string](Get-Item -LiteralPath $enginePath).VersionInfo.FileVersion
  $receiptVersion = [string]$receipt.factorio_binary_version
  $receiptProductVersion = [regex]::Match($receiptVersion, '^[0-9]+[.][0-9]+[.][0-9]+').Value
  $engineProductVersion = [regex]::Match([string]$Engine.version, '^[0-9]+[.][0-9]+[.][0-9]+').Value
  if ([string]::IsNullOrWhiteSpace($receiptProductVersion) -or [string]::IsNullOrWhiteSpace($engineProductVersion) -or
      $receiptVersion -cne [string]$Engine.version -or $fileVersion -cne [string]$Engine.version -or
      $productVersion -cne $engineProductVersion -or $receiptProductVersion -cne $productVersion) {
    throw '[mir42-individual-engine-run-engine-version]'
  }
  $candidateSourceVersion = (Get-MIR42IndividualEngineEvidenceBindingContract -Candidate $Candidate -PublishedMaintenance).maintenance_source_version
  # The seal is release evidence, so it always binds the complete Full
  # preservation oracle. Classic remains available for private
  # characterization but cannot select a reduced snapshot field here.
  if ($candidateSourceVersion -cin @('4.3.0','4.3.1') -and $receipt.Contains('upgrade_policy')) {
    $prefix = 'mir' + $candidateSourceVersion.Replace('.', '') + '-upgrade'
    throw "[$prefix-classic-reduced-policy-not-release-preservation]"
  }
  $snapshotField = 'full_state_evaluator_snapshots'
  $snapshots = if ($receipt.Contains($snapshotField)) { @($receipt[$snapshotField]) } else { @() }
  $upgradeRow = [pscustomobject]@{
    target = [string]$CandidateTarget.target
    predecessor_source_version = if ($candidateSourceVersion -ceq '4.3.1') { '4.3.0' } else { '4.2.2' }
    receipt = [pscustomobject]@{path=$receiptPath;sha256=[string]$ReceiptReference.sha256}
    snapshots = @($snapshots | ForEach-Object { [pscustomobject]@{stage=[string]$_.stage;path=[string]$_.path;sha256=[string]$_.sha256} })
  }
  $package = [pscustomobject]@{target=[string]$CandidateTarget.target;sha256=[string]$CandidateTarget.archive_sha256}
  $null = Assert-MIR423NativeUpgradeProof -Row $upgradeRow -Package $package -CandidateSourceVersion $candidateSourceVersion
  $selectedCustody = [ordered]@{
    release_id = [int64]$PublishedMaintenanceInputs.release_id
    source_tag = [string]$PublishedMaintenanceInputs.source_tag
    source = $PublishedMaintenanceInputs.source
    tag_object = [string]$PublishedMaintenanceInputs.tag_object
    remote_tag_readback = [bool]$PublishedMaintenanceInputs.remote_tag_readback
    manifest = $PublishedMaintenanceInputs.manifest
    signed = [bool]$PublishedMaintenanceInputs.signed
    targets = @($PublishedInput)
    native_qualification = [string]$PublishedMaintenanceInputs.native_qualification
    release_qualification = [string]$PublishedMaintenanceInputs.release_qualification
    local_custody_scope = 'selected-native-archive'
  }
  if ([string]$receipt.from.sha256 -cne [string]$PublishedInput.sha256 -or
      [string]$receipt.from.version -cne [string]$PublishedInput.version -or
      $receipt.published_maintenance_predecessor -isnot [Collections.IDictionary] -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $receipt.published_maintenance_predecessor) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $selectedCustody)) {
    throw '[mir42-individual-engine-run-predecessor-binding]'
  }
  $nativeCandidateArchive = Assert-MIR42IndividualNativeCandidateSelection -Receipt $receipt -ReceiptPath $receiptPath -CandidateTarget $CandidateTarget
  Assert-MIR42IndividualResourceLedgers -Receipt $receipt -ReceiptPath $receiptPath
  $root = Split-Path -Parent $receiptPath
  $logs = @(
    foreach ($phase in @('create','load','reload','second-reload')) {
      $field = if ($phase -eq 'second-reload') { 'second_reload' } else { $phase }
      $name = [string]$receipt[($field + '_log')]
      $sha = [string]$receipt[($field + '_log_sha256')]
      if ($name -cne [IO.Path]::GetFileName($name)) { throw '[mir42-individual-engine-run-log-path]' }
      $path = Resolve-MIR42SealImmutableFile -Path (Join-Path $root $name) -Sha256 $sha -Code 'mir42-individual-engine-run-log'
      [pscustomobject][ordered]@{phase=$phase;path=$path;sha256=$sha}
    }
  )
  return [pscustomobject][ordered]@{
    receipt_path = $receiptPath
    receipt_sha256 = [string]$ReceiptReference.sha256
    factorio_processes = [int]$receipt.factorio_processes
    native_candidate_archive = $nativeCandidateArchive
    execution = [pscustomobject][ordered]@{
      executable_path = $enginePath
      executable_sha256 = [string]$Engine.sha256
      version = [string]$Engine.version
      predecessor = [pscustomobject][ordered]@{path=[string]$PublishedInput.path;sha256=[string]$PublishedInput.sha256;version=[string]$PublishedInput.version}
      fresh_loads = @()
      harness_receipt = [pscustomobject][ordered]@{path=$receiptPath;sha256=[string]$ReceiptReference.sha256}
      harness_exit_code = 0
      logs = $logs
      fresh_exact_load = $true
      predecessor_upgrade = $true
      reload_count = 2
      published_maintenance_predecessor = $PublishedInput
    }
  }
}

function Get-MIR42BoundIndividualEngineRun {
  param([Parameter(Mandatory)]$Reference,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$PublishedMaintenanceInputs)
  Assert-MIR42SealPropertyNames -Value $Reference -Expected @('path','sha256','record_sha256') -Code 'mir42-individual-engine-run-reference-shape'
  $inputPath = Resolve-MIR42SealImmutableFile -Path ([string]$Reference.path) -Sha256 ([string]$Reference.sha256) -Code 'mir42-individual-engine-run-reference'
  $input = Read-MIR42SealRecord -Path $inputPath -Code 'mir42-individual-engine-run'
  $record = $input.record
  if ([string]$record.record_sha256 -cne [string]$Reference.record_sha256) { throw '[mir42-individual-engine-run-reference-binding]' }
  $contract = Get-MIR42IndividualEngineEvidenceBindingContract -Candidate $Candidate -PublishedMaintenance
  $expectedProperties = @('schema','kind','status','source','candidate_manifest','predecessor_authority','public_v410_checksum_asset','runner','harness','historical_target_authorities','published_maintenance_predecessor','individual_upgrade_receipts','fresh_loads','factorio_processes','release_qualification','publication_authorized','record_sha256')
  Assert-MIR42SealPropertyNames -Value $record -Expected $expectedProperties -Code 'mir42-individual-engine-run-shape'
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne [string]$contract.engine_run_kind -or
      [string]$record.status -cne [string]$contract.engine_run_status -or
      [string]$record.source.commit -cne [string]$Candidate.source.commit -or
      [string]$record.source.tree -cne [string]$Candidate.source.tree -or
      [string]$record.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256 -or
      [string]$record.candidate_manifest.sha256 -cne [string]$Candidate.identity.sha256 -or
      [string]$record.candidate_manifest.record_sha256 -cne [string]$Candidate.identity.record.record_sha256 -or
      [string]$record.release_qualification -cne 'not-performed' -or [bool]$record.publication_authorized) {
    throw '[mir42-individual-engine-run-state]'
  }
  Assert-MIR42EngineEvidenceMaintenanceCustody -Recorded $record.published_maintenance_predecessor -Current $PublishedMaintenanceInputs -Code 'mir42-individual-engine-run-custody-binding'
  foreach ($field in @('candidate_manifest','runner','harness')) {
    $expected = if ($field -eq 'candidate_manifest') { @('path','sha256','record_sha256') } else { @('path','sha256') }
    Assert-MIR42SealPropertyNames -Value $record.$field -Expected $expected -Code "mir42-individual-engine-run-$field-shape"
    $path = Resolve-MIR42SealImmutableFile -Path ([string]$record.$field.path) -Sha256 ([string]$record.$field.sha256) -Code "mir42-individual-engine-run-$field"
    if ($field -eq 'candidate_manifest') {
      $manifest = Read-MIR42SealRecord -Path $path -Code 'mir42-individual-engine-run-candidate-manifest'
      if ([string]$manifest.sha256 -cne [string]$Candidate.identity.sha256 -or [string]$manifest.record.record_sha256 -cne [string]$Candidate.identity.record.record_sha256) {
        throw '[mir42-individual-engine-run-candidate-manifest-binding]'
      }
    } elseif ((Get-Content -Raw -LiteralPath $path) -notmatch 'Test-MIRUpgrade[.]ps1') {
      throw "[mir42-individual-engine-run-$field-content]"
    }
  }
  Assert-MIR42SealPropertyNames -Value $record.predecessor_authority -Expected @('path','sha256','record_sha256') -Code 'mir42-individual-engine-run-predecessor-authority-shape'
  Assert-MIR42SealPropertyNames -Value $record.public_v410_checksum_asset -Expected @('release_id','asset_id','digest','bytes','download_verified') -Code 'mir42-individual-engine-run-checksum-shape'
  $historicalTargets = @($record.historical_target_authorities | ForEach-Object { [string]$_.target })
  if ($historicalTargets.Count -ne $script:MIR42SealHistoricalTargets.Count -or ($historicalTargets -join '|') -cne ($script:MIR42SealHistoricalTargets -join '|')) {
    throw '[mir42-individual-engine-run-historical-target-set]'
  }
  foreach ($historical in @($record.historical_target_authorities)) {
    Assert-MIR42SealPropertyNames -Value $historical -Expected @('target','authority') -Code 'mir42-individual-engine-run-historical-authority-shape'
  }
  $receiptTargets = @($record.individual_upgrade_receipts | ForEach-Object { [string]$_.target })
  Assert-MIR42SealTargetSet -Rows @($record.individual_upgrade_receipts) -Scope 'nine-target' -Code 'mir42-individual-engine-run-receipt'
  if (($receiptTargets -join '|') -cne ($script:MIR42SealNineTargetCandidates -join '|')) { throw '[mir42-individual-engine-run-receipt-order]' }
  $expectedFresh = @()
  foreach ($target in $script:MIR42SealNineTargetCandidates) {
    foreach ($scenario in $(if ($target -ceq 'f210') { @('package-zip-base','package-zip-space-age') } else { @('package-zip-base') })) {
      $expectedFresh += ($target + '|' + $scenario)
    }
  }
  $actualFresh = @($record.fresh_loads | ForEach-Object { [string]$_.target + '|' + [string]$_.scenario })
  if ($actualFresh.Count -ne $expectedFresh.Count -or ($actualFresh -join '|') -cne ($expectedFresh -join '|')) { throw '[mir42-individual-engine-run-fresh-set]' }
  $results = [Collections.Generic.List[object]]::new()
  [int]$processTotal = 0
  foreach ($candidateTarget in @($Candidate.targets)) {
    $target = [string]$candidateTarget.target
    $receiptRows = @($record.individual_upgrade_receipts | Where-Object { [string]$_.target -ceq $target })
    $publishedRows = @($PublishedMaintenanceInputs.targets | Where-Object { [string]$_.target -ceq $target })
    if ($receiptRows.Count -ne 1 -or $publishedRows.Count -ne 1) { throw "[mir42-individual-engine-run-receipt-cardinality] $target" }
    Assert-MIR42SealPropertyNames -Value $receiptRows[0] -Expected @('target','engine','receipt','harness_exit_code') -Code 'mir42-individual-engine-run-receipt-row-shape'
    $proof = Assert-MIR42IndividualUpgradeReceipt -ReceiptReference $receiptRows[0].receipt -CandidateTarget $candidateTarget -PublishedInput $publishedRows[0] -PublishedMaintenanceInputs $PublishedMaintenanceInputs -Engine $receiptRows[0].engine -HarnessExitCode ([int]$receiptRows[0].harness_exit_code) -Candidate $Candidate
    $execution = $proof.execution
    $freshRows = @($record.fresh_loads | Where-Object { [string]$_.target -ceq $target })
    $execution.fresh_loads = @(
      foreach ($fresh in $freshRows) {
        Assert-MIR42SealPropertyNames -Value $fresh -Expected @('target','scenario','receipt','log','stdout','stderr') -Code 'mir42-individual-engine-run-fresh-row-shape'
        foreach ($field in @('receipt','log','stdout','stderr')) {
          Assert-MIR42SealPropertyNames -Value $fresh.$field -Expected @('path','sha256') -Code "mir42-individual-engine-run-fresh-$field-shape"
          $null = Resolve-MIR42SealImmutableFile -Path ([string]$fresh.$field.path) -Sha256 ([string]$fresh.$field.sha256) -Code "mir42-individual-engine-run-fresh-$field"
        }
        [pscustomobject][ordered]@{scenario=[string]$fresh.scenario;receipt=$fresh.receipt;log=$fresh.log;stdout=$fresh.stdout;stderr=$fresh.stderr}
      }
    )
    if ($target -in $script:MIR42SealHistoricalTargets) {
      $historical = @($record.historical_target_authorities | Where-Object { [string]$_.target -ceq $target })
      if ($historical.Count -ne 1) { throw "[mir42-individual-engine-run-historical-cardinality] $target" }
      $execution | Add-Member -NotePropertyName historical_terminal_authority -NotePropertyValue $historical[0].authority
    }
    $freshTarget = [pscustomobject]@{
      target=$target
      target_id=(Get-MIR42ReleaseTargetIdentity -RepoRoot $mir42SealRepoRoot -Target $target -SourceVersion $contract.maintenance_source_version).target_id
      distribution_version=[string]$candidateTarget.distribution_version
      archive=[pscustomobject]@{
        path=[string]$proof.native_candidate_archive.path
        sha256=[string]$candidateTarget.archive_sha256
        content_sha256=[string]$candidateTarget.content_sha256
      }
    }
    $freshCandidateTarget = [pscustomobject][ordered]@{
      target=$target;distribution_version=[string]$candidateTarget.distribution_version;archive_sha256=[string]$candidateTarget.archive_sha256
      content_sha256=[string]$candidateTarget.content_sha256;archive_path=[string]$candidateTarget.archive_path;source=$Candidate.source
    }
    Assert-MIR42FreshEngineLoads -Target $freshTarget -CandidateTarget $freshCandidateTarget -Execution $execution
    $processTotal += [int]$proof.factorio_processes + $freshRows.Count
    $results.Add([pscustomobject][ordered]@{
      target = $target;status='passed';archive=$proof.native_candidate_archive;engine_execution=$execution
    })
  }
  if ([int]$record.factorio_processes -ne $processTotal) { throw '[mir42-individual-engine-run-process-count]' }
  $constructed = [pscustomobject][ordered]@{
    schema=1;kind=[string]$record.kind;status=[string]$record.status;source=$record.source;candidate_manifest=$record.candidate_manifest
    predecessor_authority=$record.predecessor_authority;public_v410_checksum_asset=$record.public_v410_checksum_asset;runner=$record.runner;harness=$record.harness
    targets=@($results.ToArray());factorio_processes=$processTotal;release_qualification='not-performed';publication_authorized=$false
    historical_target_authorities=$record.historical_target_authorities;published_maintenance_predecessor=$record.published_maintenance_predecessor;record_sha256=[string]$record.record_sha256
  }
  return [pscustomobject][ordered]@{path=$input.path;sha256=$input.sha256;record=$constructed;input_kind='individual-upgrade-receipts-and-fresh-loads'}
}

function New-MIR42FourTargetRealEngineEvidenceBinder {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$EvidenceReconciliationPath,
    [Parameter(Mandatory)][string]$EngineRunPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$PublishedMaintenancePredecessorManifestPath = '',
    [System.Collections.IDictionary]$PublishedMaintenanceArchiveBindings = $null
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if ($null -ne $PublishedMaintenanceArchiveBindings -and [string]::IsNullOrWhiteSpace($PublishedMaintenancePredecessorManifestPath)) {
    throw '[mir42-engine-evidence-maintenance-archive-bindings-scope]'
  }
  $candidate = Get-MIR42ExactFourTargetCandidate -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath
  $scope = Get-MIR42SealCandidateScope -Candidate $candidate -Code 'mir42-engine-evidence-candidate'
  $maintenanceRequested = -not [string]::IsNullOrWhiteSpace($PublishedMaintenancePredecessorManifestPath)
  $engineInput = Read-MIR42SealRecord -Path $EngineRunPath -Code 'mir42-engine-evidence-engine-run'
  $individualNativeInput = [string]$engineInput.record.kind -ceq 'MIR42NineTargetMaintenanceIndividualEngineRunV1'
  $contract = if ($individualNativeInput) {
    Get-MIR42IndividualEngineEvidenceBindingContract -Candidate $candidate -PublishedMaintenance:$maintenanceRequested
  } else {
    Get-MIR42EngineEvidenceBindingContract -Candidate $candidate -PublishedMaintenance:$maintenanceRequested
  }
  $maintenanceInputs = $null
  if ($maintenanceRequested) {
    $predecessorContract = Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion $contract.maintenance_source_version
    $metadataText = (& gh api ('repos/Julesc013/more-infinite-research/releases/tags/' + $predecessorContract.source_tag) | Out-String)
    if ($LASTEXITCODE -ne 0) { throw '[mir42-engine-evidence-maintenance-release-readback]' }
    $maintenanceArguments = @{RepoRoot=$repo;ManifestPath=$PublishedMaintenancePredecessorManifestPath
      ReleaseMetadata=($metadataText | ConvertFrom-Json -Depth 100 -DateKind String);CandidateSourceVersion=$contract.maintenance_source_version}
    if ($null -ne $PublishedMaintenanceArchiveBindings) { $maintenanceArguments.ArchiveBindings = $PublishedMaintenanceArchiveBindings }
    $maintenanceInputs = Get-MIR42PublishedMaintenancePredecessorInputs @maintenanceArguments
  }
  $reconciliation = Get-MIR42ExactQualificationReceipt -Path $EvidenceReconciliationPath -Candidate $candidate -PublishedMaintenanceInputs $maintenanceInputs
  $engineRun = Get-MIR42BoundEngineRun -Reference ([pscustomobject][ordered]@{
    path = $engineInput.path
    sha256 = $engineInput.sha256
    record_sha256 = [string]$engineInput.record.record_sha256
  }) -Candidate $candidate -PublishedMaintenanceInputs $maintenanceInputs
  $targets = [Collections.Generic.List[object]]::new()
  foreach ($candidateTarget in @($candidate.targets)) {
    $engineTarget = @($engineRun.record.targets | Where-Object { [string]$_.target -ceq [string]$candidateTarget.target })
    if ($engineTarget.Count -ne 1) { throw "[mir42-engine-evidence-target-cardinality] $([string]$candidateTarget.target)" }
    $targets.Add([pscustomobject][ordered]@{
      target = [string]$candidateTarget.target
      distribution_version = [string]$candidateTarget.distribution_version
      status = 'observed-real-engine-private-unqualified'
      archive = [ordered]@{
        sha256 = [string]$candidateTarget.archive_sha256
        content_sha256 = [string]$candidateTarget.content_sha256
        entry_count = [int]$candidateTarget.entry_count
      }
      engine_execution = $engineTarget[0].engine_execution
    })
  }
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = [string]$contract.binder_kind
    status = [string]$contract.binder_status
    source = $candidate.source
    candidate_manifest = [ordered]@{sha256=[string]$candidate.identity.sha256;record_sha256=[string]$candidate.identity.record.record_sha256}
    evidence_reconciliation = [ordered]@{sha256=[string]$reconciliation.sha256;record_sha256=[string]$reconciliation.record.record_sha256}
    engine_run = [ordered]@{path=[string]$engineRun.path;sha256=[string]$engineRun.sha256;record_sha256=[string]$engineRun.record.record_sha256}
    runner = [ordered]@{sha256=[string]$engineRun.record.runner.sha256}
    targets = @($targets)
    factorio_processes = [int]$engineRun.record.factorio_processes
    release_qualification = 'not-performed'
    release_acceptance = 'not-performed'
    technical_seal = 'not-performed'
    publication_authorized = $false
    record_sha256 = ''
  }
  if ($null -ne $maintenanceInputs) { $record | Add-Member -NotePropertyName published_maintenance_predecessor -NotePropertyValue $maintenanceInputs }
  if ($individualNativeInput) { $record | Add-Member -NotePropertyName engine_input_kind -NotePropertyValue 'individual-upgrade-receipts-and-fresh-loads' }
  return (Write-MIR42NormalizedRecord -Record $record -OutputPath $OutputPath -Code 'mir42-engine-evidence-output')
}

function Assert-MIR430SealPerformanceCriterionEvidence {
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)]$Candidate)

  $version = Get-MIR42SealCandidateConstructionVersionContract -RepoRoot $mir42SealRepoRoot -Manifest $Candidate.identity.record
  if ([string]$version.source_version -cnotin @('4.3.0','4.3.1')) { return }
  $evidence = @($Record.evidence)
  if ($evidence.Count -ne 1) { throw '[mir430-seal-performance-evidence-count]' }
  $path = Resolve-MIR42SealImmutableFile -Path ([string]$evidence[0].path) -Sha256 ([string]$evidence[0].sha256) -Code 'mir430-seal-performance-observation'
  $adapterRows = @(
    foreach ($target in @($Candidate.targets)) {
      [pscustomobject][ordered]@{
        target = [string]$target.target
        identity = [pscustomobject][ordered]@{distribution_version=[string]$target.distribution_version}
        archive = [pscustomobject][ordered]@{
          path = [string]$target.archive_path
          sha256 = [string]$target.archive_sha256
          bytes = [int64](Get-Item -LiteralPath ([string]$target.archive_path)).Length
          content_sha256 = [string]$target.content_sha256
          entry_count = [int]$target.entry_count
        }
      }
    }
  )
  $adapter = [pscustomobject][ordered]@{
    source = $Candidate.source
    candidate_manifest = [pscustomobject][ordered]@{sha256=[string]$Candidate.identity.sha256;record_sha256=[string]$Candidate.identity.record.record_sha256}
    source_version = [string]$version.source_version
    target_rows = $adapterRows
  }
  $verified = Assert-MIR430ClassicStartupStressObservation -RepoRoot $mir42SealRepoRoot -Path $path -Candidate $adapter -Code 'mir430-seal-performance-observation'
  if ([string]$verified.record.record_sha256 -cne [string]$evidence[0].record_sha256) { throw '[mir430-seal-performance-observation-binding]' }
}

function Get-MIR42NineTargetCriterionEvidenceRecord {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate)

  $identity = Read-MIR42SealRecord -Path $Path -Code 'mir42-joined-campaign-criterion'
  $record = $identity.record
  Assert-MIR42SealPropertyNames -Value $record -Expected @('schema','kind','status','criterion','source','candidate_manifest','observed_targets','not_applicable_targets','evidence','limits','record_sha256') -Code 'mir42-joined-campaign-criterion-shape'
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42NineTargetReleaseAcceptanceCriterionEvidenceV1' -or
      [string]$record.status -cne 'passed' -or [string]$record.criterion -notin $script:MIR42SealReleaseAcceptanceCriteria -or
      [string]$record.source.commit -cne [string]$Candidate.source.commit -or
      [string]$record.source.tree -cne [string]$Candidate.source.tree -or
      [string]$record.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256 -or
      [string]$record.candidate_manifest.sha256 -cne [string]$Candidate.identity.sha256 -or
      [string]$record.candidate_manifest.record_sha256 -cne [string]$Candidate.identity.record.record_sha256) {
    throw '[mir42-joined-campaign-criterion-binding]'
  }
  if ([string]$record.criterion -ceq 'performance-telemetry') {
    Assert-MIR430SealPerformanceCriterionEvidence -Record $record -Candidate $Candidate
  }
  return $identity
}

function New-MIR42NineTargetJoinedRealEngineCampaign {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$EvidenceReconciliationPath,
    [Parameter(Mandatory)][string]$EngineEvidencePath,
    [Parameter(Mandatory)][string[]]$CriterionEvidencePaths,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$PublishedMaintenancePredecessorManifestPath = '',
    [System.Collections.IDictionary]$PublishedMaintenanceArchiveBindings = $null
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if ($null -ne $PublishedMaintenanceArchiveBindings -and [string]::IsNullOrWhiteSpace($PublishedMaintenancePredecessorManifestPath)) {
    throw '[mir42-joined-campaign-maintenance-archive-bindings-scope]'
  }
  $candidate = Get-MIR42ExactFourTargetCandidate -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath
  Assert-MIR42SealTargetSet -Rows @($candidate.targets) -Scope 'nine-target' -Code 'mir42-joined-campaign-candidate'
  $maintenanceRequested = -not [string]::IsNullOrWhiteSpace($PublishedMaintenancePredecessorManifestPath)
  $binder = Read-MIR42SealRecord -Path $EngineEvidencePath -Code 'mir42-joined-campaign-engine-evidence'
  $individualNativeInput = [string]$binder.record.kind -ceq 'MIR42NineTargetMaintenanceIndividualRealEngineEvidenceBinderV1'
  $contract = Get-MIR42JoinedCampaignInputContract -Candidate $candidate -PublishedMaintenance:$maintenanceRequested -IndividualNativeInput:$individualNativeInput
  $maintenanceInputs = $null
  if ($maintenanceRequested) {
    $predecessorContract = Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion $contract.maintenance_source_version
    $metadataText = (& gh api ('repos/Julesc013/more-infinite-research/releases/tags/' + $predecessorContract.source_tag) | Out-String)
    if ($LASTEXITCODE -ne 0) { throw '[mir42-joined-campaign-maintenance-release-readback]' }
    $maintenanceArguments = @{RepoRoot=$repo;ManifestPath=$PublishedMaintenancePredecessorManifestPath
      ReleaseMetadata=($metadataText | ConvertFrom-Json -Depth 100 -DateKind String);CandidateSourceVersion=$contract.maintenance_source_version}
    if ($null -ne $PublishedMaintenanceArchiveBindings) { $maintenanceArguments.ArchiveBindings = $PublishedMaintenanceArchiveBindings }
    $maintenanceInputs = Get-MIR42PublishedMaintenancePredecessorInputs @maintenanceArguments
  }
  $reconciliation = Get-MIR42ExactQualificationReceipt -Path $EvidenceReconciliationPath -Candidate $candidate -PublishedMaintenanceInputs $maintenanceInputs
  $binderProperties = @('schema','kind','status','source','candidate_manifest','evidence_reconciliation','engine_run','runner','targets','factorio_processes','release_qualification','release_acceptance','technical_seal','publication_authorized','record_sha256')
  if ($maintenanceRequested) { $binderProperties += 'published_maintenance_predecessor' }
  if ($individualNativeInput) { $binderProperties += 'engine_input_kind' }
  Assert-MIR42SealPropertyNames -Value $binder.record -Expected $binderProperties -Code 'mir42-joined-campaign-engine-evidence-shape'
  if ([int]$binder.record.schema -ne 1 -or [string]$binder.record.kind -cne [string]$contract.binder_kind -or
      [string]$binder.record.status -cne [string]$contract.binder_status -or
      [string]$binder.record.evidence_reconciliation.sha256 -cne [string]$reconciliation.sha256 -or
      [string]$binder.record.evidence_reconciliation.record_sha256 -cne [string]$reconciliation.record.record_sha256 -or
      [string]$binder.record.release_qualification -cne 'not-performed' -or [string]$binder.record.release_acceptance -cne 'not-performed' -or
      [string]$binder.record.technical_seal -cne 'not-performed' -or [bool]$binder.record.publication_authorized -or
      ($individualNativeInput -and [string]$binder.record.engine_input_kind -cne 'individual-upgrade-receipts-and-fresh-loads')) {
    throw '[mir42-joined-campaign-engine-evidence-binding]'
  }
  Assert-MIR42ReceiptBinding -Receipt $binder -Candidate $candidate -Code 'mir42-joined-campaign-engine-evidence' -ExpectedTargetStatus 'observed-real-engine-private-unqualified'
  if ($maintenanceRequested) { Assert-MIR42MaintenanceCampaignCustody -Record $binder.record -PublishedInputs $maintenanceInputs }
  $engineRun = Get-MIR42BoundEngineRun -Reference $binder.record.engine_run -Candidate $candidate -PublishedMaintenanceInputs $maintenanceInputs
  if ([int]$binder.record.factorio_processes -ne [int]$engineRun.record.factorio_processes -or
      [string]$binder.record.runner.sha256 -cne [string]$engineRun.record.runner.sha256) {
    throw '[mir42-joined-campaign-engine-evidence-run-binding]'
  }
  if ($CriterionEvidencePaths.Count -ne $script:MIR42SealReleaseAcceptanceCriteria.Count) { throw '[mir42-joined-campaign-criterion-count]' }
  $criteriaByName = @{}
  foreach ($path in $CriterionEvidencePaths) {
    $criterion = Get-MIR42NineTargetCriterionEvidenceRecord -Path $path -Candidate $candidate
    $name = [string]$criterion.record.criterion
    if ($criteriaByName.ContainsKey($name)) { throw "[mir42-joined-campaign-criterion-duplicate] $name" }
    $criteriaByName[$name] = $criterion
  }
  if ((@($criteriaByName.Keys | Sort-Object { [array]::IndexOf($script:MIR42SealReleaseAcceptanceCriteria, [string]$_) }) -join '|') -cne ($script:MIR42SealReleaseAcceptanceCriteria -join '|')) {
    throw '[mir42-joined-campaign-criterion-set]'
  }
  $acceptance = @(
    foreach ($name in $script:MIR42SealReleaseAcceptanceCriteria) {
      $criteriaByName[$name].record | Select-Object criterion,status,observed_targets,not_applicable_targets,evidence,limits
    }
  )
  $provisional = [pscustomobject][ordered]@{record=[pscustomobject][ordered]@{release_acceptance=$acceptance}}
  Assert-MIR42JoinedAcceptanceCoverage -RepoRoot $repo -Receipt $provisional -Candidate $candidate
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = [string]$contract.campaign_kind
    status = [string]$contract.campaign_status
    source = $candidate.source
    candidate_manifest = [ordered]@{sha256=[string]$candidate.identity.sha256;record_sha256=[string]$candidate.identity.record.record_sha256}
    evidence_reconciliation = [ordered]@{sha256=[string]$reconciliation.sha256;record_sha256=[string]$reconciliation.record.record_sha256}
    engine_run = [ordered]@{path=[string]$engineRun.path;sha256=[string]$engineRun.sha256;record_sha256=[string]$engineRun.record.record_sha256}
    runner = $engineRun.record.runner
    targets = $binder.record.targets
    factorio_processes = [int]$engineRun.record.factorio_processes
    release_qualification = 'passed'
    release_acceptance = $acceptance
    technical_seal = 'not-performed'
    publication_authorized = $false
    record_sha256 = ''
  }
  if ($maintenanceRequested) { $record | Add-Member -NotePropertyName published_maintenance_predecessor -NotePropertyValue $maintenanceInputs }
  if ($individualNativeInput) { $record | Add-Member -NotePropertyName engine_input_kind -NotePropertyValue 'individual-upgrade-receipts-and-fresh-loads' }
  # Validate the assembled campaign before writing an artifact that claims a
  # native pass. The output readback repeats the same checks on its exact bytes.
  $provisionalCampaign = [pscustomobject]@{record=$record}
  Assert-MIR42RealEngineCampaignExecution -RepoRoot $repo -Campaign $provisionalCampaign -Candidate $candidate -EngineRun $engineRun -PublishedMaintenanceInputs $maintenanceInputs
  $written = Write-MIR42NormalizedRecord -Record $record -OutputPath $OutputPath -Code 'mir42-joined-campaign-output'
  $readback = Get-MIR42RealEngineCandidateCampaign -RepoRoot $repo -Path $OutputPath -Candidate $candidate -Reconciliation $reconciliation -PublishedMaintenanceInputs $maintenanceInputs
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $written) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $readback.record)) {
    throw '[mir42-joined-campaign-output-readback]'
  }
  return $readback.record
}

function Get-MIR42RealEngineCandidateCampaign {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Reconciliation,$PublishedMaintenanceInputs = $null)
  $scope = Get-MIR42SealCandidateScope -Candidate $Candidate -Code 'mir42-seal-real-engine-candidate'
  $campaign = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-real-engine'
  $record = $campaign.record
  $individualNativeInput = [string]$record.kind -ceq 'MIR42NineTargetMaintenanceIndividualRealEngineCandidateCampaignV1'
  $contract = Get-MIR42JoinedCampaignInputContract -Candidate $Candidate -PublishedMaintenance:($null -ne $PublishedMaintenanceInputs) -IndividualNativeInput:$individualNativeInput
  $campaignProperties = @('schema','kind','status','source','candidate_manifest','evidence_reconciliation','engine_run','runner','targets','factorio_processes','release_qualification','release_acceptance','technical_seal','publication_authorized','record_sha256')
  if ($null -ne $PublishedMaintenanceInputs) { $campaignProperties += 'published_maintenance_predecessor' }
  if ($individualNativeInput) { $campaignProperties += 'engine_input_kind' }
  Assert-MIR42SealPropertyNames -Value $record -Expected $campaignProperties -Code 'mir42-seal-real-engine-shape'
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne [string]$contract.campaign_kind -or
      [string]$record.status -cne [string]$contract.campaign_status -or
      [string]$record.evidence_reconciliation.sha256 -cne [string]$Reconciliation.sha256 -or
      [string]$record.evidence_reconciliation.record_sha256 -cne [string]$Reconciliation.record.record_sha256 -or
      [int]$record.factorio_processes -lt 4 -or
      [string]$record.release_qualification -cne 'passed' -or
      [string]$record.technical_seal -cne 'not-performed' -or
      [bool]$record.publication_authorized -or
      ($individualNativeInput -and [string]$record.engine_input_kind -cne 'individual-upgrade-receipts-and-fresh-loads')) {
    throw '[mir42-seal-real-engine-campaign-state]'
  }
  Assert-MIR42SealPropertyNames -Value $record.runner -Expected @('path','sha256') -Code 'mir42-seal-real-engine-runner-shape'
  $runnerPath = Resolve-MIR42SealImmutableFile -Path ([string]$record.runner.path) -Sha256 ([string]$record.runner.sha256) -Code 'mir42-seal-real-engine-runner'
  if ((Get-Content -Raw -LiteralPath $runnerPath) -notmatch 'Invoke-MIR42FourTargetEngineRun|Test-MIRUpgrade') { throw '[mir42-seal-real-engine-runner-content]' }
  Assert-MIR42ReceiptBinding -Receipt $campaign -Candidate $Candidate -Code 'mir42-seal-real-engine'
  if ($null -ne $PublishedMaintenanceInputs) { Assert-MIR42MaintenanceCampaignCustody -Record $record -PublishedInputs $PublishedMaintenanceInputs }
  $engineRun = Get-MIR42BoundEngineRun -Reference $record.engine_run -Candidate $Candidate -PublishedMaintenanceInputs $PublishedMaintenanceInputs
  if ([string]$record.runner.sha256 -cne [string]$engineRun.record.runner.sha256) { throw '[mir42-seal-real-engine-runner-binding]' }
  Assert-MIR42RealEngineCampaignExecution -RepoRoot $RepoRoot -Campaign $campaign -Candidate $Candidate -EngineRun $engineRun -PublishedMaintenanceInputs $PublishedMaintenanceInputs
  return $campaign
}

function Assert-MIR42RealEngineCampaignExecution {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Campaign,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$EngineRun,$PublishedMaintenanceInputs = $null)
  $record = $Campaign.record
  if ([int]$record.factorio_processes -ne [int]$engineRun.record.factorio_processes) { throw '[mir42-seal-real-engine-process-count-binding]' }
  if ($null -ne $PublishedMaintenanceInputs) { Assert-MIR42MaintenanceCampaignCustody -Record $record -PublishedInputs $PublishedMaintenanceInputs }
  foreach ($target in @($record.targets)) {
    $candidateTarget = @($Candidate.targets | Where-Object { [string]$_.target -ceq [string]$target.target })[0]
    $engineRunTarget = @($engineRun.record.targets | Where-Object { [string]$_.target -ceq [string]$target.target })[0]
    if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $target.engine_execution) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $engineRunTarget.engine_execution)) {
      throw "[mir42-seal-real-engine-run-binding] $([string]$target.target)"
    }
    $executionProperties = @('executable_path','executable_sha256','version','predecessor','harness_receipt','harness_exit_code','logs','fresh_loads','fresh_exact_load','predecessor_upgrade','reload_count')
    if ([string]$target.target -in $script:MIR42SealHistoricalTargets) { $executionProperties += 'historical_terminal_authority' }
    if ($null -ne $PublishedMaintenanceInputs) { $executionProperties += 'published_maintenance_predecessor' }
    Assert-MIR42SealPropertyNames -Value $target.engine_execution -Expected $executionProperties -Code 'mir42-seal-real-engine-target-shape'
    Assert-MIR42SealPropertyNames -Value $target.engine_execution.predecessor -Expected @('path','sha256','version') -Code 'mir42-seal-real-engine-predecessor-shape'
    Assert-MIR42SealPropertyNames -Value $target.engine_execution.harness_receipt -Expected @('path','sha256') -Code 'mir42-seal-real-engine-receipt-shape'
    $executablePath = Resolve-MIR42SealImmutableFile -Path ([string]$target.engine_execution.executable_path) -Sha256 ([string]$target.engine_execution.executable_sha256) -Code 'mir42-seal-real-engine-executable'
    $predecessorPath = Resolve-MIR42SealImmutableFile -Path ([string]$target.engine_execution.predecessor.path) -Sha256 ([string]$target.engine_execution.predecessor.sha256) -Code 'mir42-seal-real-engine-predecessor'
    $harnessPath = Resolve-MIR42SealImmutableFile -Path ([string]$target.engine_execution.harness_receipt.path) -Sha256 ([string]$target.engine_execution.harness_receipt.sha256) -Code 'mir42-seal-real-engine-receipt'
    try { $harness = Get-Content -Raw -LiteralPath $harnessPath | ConvertFrom-Json -Depth 100 -DateKind String } catch { throw '[mir42-seal-real-engine-receipt-json]' }
    $logs = @($target.engine_execution.logs)
    $logPhases = @($logs | ForEach-Object { [string]$_.phase })
    foreach ($log in $logs) {
      Assert-MIR42SealPropertyNames -Value $log -Expected @('phase','path','sha256') -Code 'mir42-seal-real-engine-log-shape'
      $null = Resolve-MIR42SealImmutableFile -Path ([string]$log.path) -Sha256 ([string]$log.sha256) -Code 'mir42-seal-real-engine-log'
    }
    $requiredAssertions = @('exact-candidate-normal-mod-directory-load','upgraded-save-reload-passed','upgraded-save-second-reload-passed')
    if ([string]$target.target -in $script:MIR42SealHistoricalTargets) {
      $requiredAssertions += @('historical-terminal-source-state-retained','historical-terminal-researched-level-retained',
        'historical-terminal-current-research-retained','historical-terminal-fractional-progress-retained',
        'historical-terminal-infinite-bonus-retained-where-supported','historical-terminal-global-state-retained')
    }
    $missingAssertions = @($requiredAssertions | Where-Object { $_ -cnotin @($harness.assertions | ForEach-Object { [string]$_ }) })
    if ([string]$target.engine_execution.executable_sha256 -notmatch '^[A-F0-9]{64}$' -or
        [string]::IsNullOrWhiteSpace([string]$target.engine_execution.version) -or
        [int]$target.engine_execution.harness_exit_code -ne 0 -or @($logs).Count -ne 4 -or
        ($logPhases -join '|') -cne 'create|load|reload|second-reload' -or
        @($logs | Where-Object { [string]$_.sha256 -notmatch '^[A-F0-9]{64}$' }).Count -ne 0 -or
        -not [bool]$target.engine_execution.fresh_exact_load -or
        -not [bool]$target.engine_execution.predecessor_upgrade -or [int]$target.engine_execution.reload_count -lt 2 -or
        [string]$harness.status -cne 'passed' -or [string]$harness.git_commit -cne [string]$Candidate.source.commit -or
        [string]$harness.factorio_binary_sha256 -cne [string]$target.engine_execution.executable_sha256 -or
        [string]$harness.factorio_binary_version -cne [string]$target.engine_execution.version -or
        [string]$harness.from.sha256 -cne [string]$target.engine_execution.predecessor.sha256 -or
        [string]$harness.from.version -cne [string]$target.engine_execution.predecessor.version -or
        [string]$harness.to.sha256 -cne [string]$candidateTarget.archive_sha256 -or
        [string]$harness.to.path -cne [IO.Path]::GetFileName([string]$candidateTarget.archive_path) -or
        $missingAssertions.Count -ne 0) {
      throw "[mir42-seal-real-engine-target-binding] $([string]$target.target)"
    }
    foreach ($log in $logs) {
      $text = Get-Content -Raw -LiteralPath ([string]$log.path)
      $marker = switch ([string]$log.phase) {
        'create' { '[mir-fixture]' }
        'load' { 'upgrade proof complete' }
        default { 'upgraded save reload proof complete' }
      }
      if (-not $text.Contains($marker)) { throw "[mir42-seal-real-engine-log-marker] $([string]$target.target)/$([string]$log.phase)" }
    }
    $publishedInput = $null
    if ($null -ne $PublishedMaintenanceInputs) { $publishedInput = @($PublishedMaintenanceInputs.targets | Where-Object { [string]$_.target -ceq [string]$target.target })[0] }
    if ([string]$target.target -in $script:MIR42SealHistoricalTargets) {
      $historicalProperty = if ($null -ne $PublishedMaintenanceInputs) { 'historical_target_authorities' } else { 'historical_terminal_predecessors' }
      Assert-MIR42HistoricalTerminalExecution -RepoRoot $RepoRoot -Target $target -Execution $target.engine_execution -HistoricalAuthorities $engineRun.record.$historicalProperty -PublishedMaintenanceInput $publishedInput
    } else {
      if ($null -eq $publishedInput) { Assert-MIR42ExactEngineAuthority -RepoRoot $RepoRoot -Target $target -Execution $target.engine_execution }
      Assert-MIR42GovernedPredecessor -RepoRoot $RepoRoot -Target $target -Execution $target.engine_execution -AuthorityReference $engineRun.record.predecessor_authority -RunAsset $engineRun.record.public_v410_checksum_asset -PublishedMaintenanceInput $publishedInput
    }
    Assert-MIR42FreshEngineLoads -Target $target -CandidateTarget $Candidate -Execution $target.engine_execution
  }
  Assert-MIR42JoinedAcceptanceCoverage -RepoRoot $RepoRoot -Receipt $Campaign -Candidate $Candidate
}

function Get-MIR42ExactIndependentVerificationReceipt {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Qualification,$PublishedMaintenanceInputs = $null)
  $scope = Get-MIR42SealCandidateScope -Candidate $Candidate -Code 'mir42-seal-independent-candidate'
  $contract = Get-MIR42SealIndependentInputContract -Candidate $Candidate -PublishedMaintenance:($null -ne $PublishedMaintenanceInputs)
  $receipt = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-independent'
  $properties = @('schema','kind','status','source','evaluator','candidate_manifest','qualification','targets',$contract.independent_target_requirement,'factorio_processes','release_qualification','independent_release_acceptance','technical_seal','signing_authorized','publication_authorized','record_sha256')
  if ($null -ne $PublishedMaintenanceInputs) { $properties += 'published_maintenance_predecessor' }
  Assert-MIR42SealPropertyNames -Value $receipt.record -Expected $properties -Code 'mir42-seal-independent-shape'
  if ([int]$receipt.record.schema -ne 1 -or [string]$receipt.record.kind -cne [string]$contract.independent_kind -or
      [string]$receipt.record.status -cne [string]$contract.independent_status -or
      -not [bool]$receipt.record.($contract.independent_target_requirement) -or
      [int]$receipt.record.factorio_processes -ne 0 -or
      [string]$receipt.record.release_qualification -cne 'not-performed' -or
      [string]$receipt.record.independent_release_acceptance -cne 'not-performed' -or
      [string]$receipt.record.technical_seal -cne 'not-performed' -or [bool]$receipt.record.signing_authorized -or
      [string]$receipt.record.qualification.sha256 -cne [string]$Qualification.sha256 -or
      [string]$receipt.record.qualification.record_sha256 -cne [string]$Qualification.record.record_sha256 -or
      [bool]$receipt.record.publication_authorized) {
    throw '[mir42-seal-independent-evidence-reconciliation-state]'
  }
  Assert-MIR42ReceiptBinding -Receipt $receipt -Candidate $Candidate -Code 'mir42-seal-independent' -ExpectedTargetStatus 'reconciled'
  if ($null -ne $PublishedMaintenanceInputs) { Assert-MIR42SealIndependentMaintenanceCustody -Record $receipt.record -PublishedInputs $PublishedMaintenanceInputs }
  return $receipt
}

function Get-MIR42SealIndependentInputContract {
  param([Parameter(Mandatory)]$Candidate,[switch]$PublishedMaintenance)
  $contract = Get-MIR42JoinedCampaignInputContract -Candidate $Candidate -PublishedMaintenance:$PublishedMaintenance
  if ($PublishedMaintenance) {
    $contract.independent_kind = 'MIR42NineTargetMaintenanceIndependentEvidenceRehashV1'
    $contract.independent_status = "MIR-$($contract.maintenance_source_version)-NINE-TARGET-MAINTENANCE-INDEPENDENT-EVIDENCE-REHASH-PASSED-PRIVATE-UNQUALIFIED"
  }
  return $contract
}

function Get-MIR42TechnicalSealInputContract {
  param([Parameter(Mandatory)]$Candidate,[switch]$PublishedMaintenance)
  $contract = Get-MIR42SealIndependentInputContract -Candidate $Candidate -PublishedMaintenance:$PublishedMaintenance
  if ($PublishedMaintenance) {
    $contract.seal_kind = 'MIR42NineTargetMaintenanceTechnicalSealV1'
    $contract.seal_status = "MIR-$($contract.maintenance_source_version)-NINE-TARGET-MAINTENANCE-TECHNICALLY-SEALED-AWAITING-PROTECTED-MAIN-PR"
  }
  return $contract
}

function Assert-MIR42SealIndependentMaintenanceCustody {
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)]$PublishedInputs)
  Assert-MIR42EngineEvidenceMaintenanceCustody -Recorded $Record.published_maintenance_predecessor -Current $PublishedInputs -Code 'mir42-seal-independent-maintenance-custody-binding'
  $actual = @($Record.targets | ForEach-Object { [string]$_.target })
  if ($actual.Count -ne $script:MIR42SealNineTargetCandidates.Count -or ($actual -join '|') -cne ($script:MIR42SealNineTargetCandidates -join '|')) {
    throw '[mir42-seal-independent-maintenance-target-set]'
  }
  foreach ($row in $Record.targets) {
    $inputs = @($PublishedInputs.targets | Where-Object { [string]$_.target -ceq [string]$row.target })
    if ($inputs.Count -ne 1 -or [string]$row.predecessor_sha256 -cne [string]$inputs[0].sha256) {
      throw '[mir42-seal-independent-maintenance-predecessor-binding]'
    }
    Assert-MIR42EngineEvidenceMaintenanceCustody -Recorded $row.published_maintenance_predecessor -Current $inputs[0] -Code ('mir42-seal-independent-maintenance-row-custody-binding-' + [string]$row.target)
  }
}

function Get-MIR42ProtectedSigningCeremony {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$T16TrustRoot)
  $receipt = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-signing'
  $schema = Join-Path $RepoRoot 'spec/schemas/mir4-protected-signing-ceremony-receipt-v1.schema.json'
  $raw = Get-Content -Raw -LiteralPath $receipt.path
  if (-not ($raw | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue)) { throw '[mir42-seal-signing-schema]' }
  if ([string]$receipt.record.status -cne 'accepted-protected-signing-authority' -or
      [string]$receipt.record.authorization.decision -cne 'AUTHORIZED' -or
      [bool]$receipt.record.secret_values_present) { throw '[mir42-seal-signing-state]' }
  $root = $T16TrustRoot.record
  if ([string]$root.signing_ceremony.path -cne [string]$receipt.path -or [string]$root.signing_ceremony.sha256 -cne [string]$receipt.sha256 -or
      [string]$root.signing_ceremony.record_sha256 -cne [string]$receipt.record.record_sha256 -or
      [string]$root.authorized_signer.principal -cne [string]$receipt.record.public_signer.principal -or
      [string]$root.authorized_signer.algorithm -cne [string]$receipt.record.public_signer.algorithm -or
      [string]$root.authorized_signer.public_key -cne [string]$receipt.record.public_signer.public_key -or
      [string]$root.authorized_signer.fingerprint -cne [string]$receipt.record.public_signer.fingerprint -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value @($root.authorized_signer.namespaces)) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value @($receipt.record.public_signer.namespaces)) -or
      [string]$receipt.record.custody_validation.approved_custodian_sid_set_sha256 -cne [string]$T16TrustRoot.acl_contract.custodian_sid_set_sha256 -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $root.recovery) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $receipt.record.recovery)) {
    throw '[mir42-seal-external-t16-signing-binding]'
  }
  return [pscustomobject][ordered]@{path=$receipt.path;sha256=$receipt.sha256;record=$receipt.record;ledger_signer=$root.authorized_signer;independent_reviewer=$root.independent_reviewer;t16_trust_root=$T16TrustRoot}
}

function Assert-MIR42SealPropertyNames {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string[]]$Expected,[Parameter(Mandatory)][string]$Code)
  $actual = @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
  if ($actual.Count -ne $Expected.Count -or @($actual | Where-Object { $_ -cnotin $Expected }).Count -ne 0) { throw "[$Code]" }
}

function New-MIR42NineTargetReleaseCutProgramme {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [switch]$RefreshPendingAuthority,
    [string]$CheckpointRoot = ''
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $previousRelative = (Get-MIR42SealScopeContract -Scope 'four-target').programme_path
  $previous = Read-MIR42SealRecord -Path (Join-Path $repo $previousRelative) -Code 'mir42-nine-programme-superseded'
  if ([string]$previous.record.kind -cne 'MIR42ReleaseCutProgrammeV1' -or
      [string]$previous.record.release_line -cne '4.2' -or
      [bool]$previous.record.release_transition_authority -or [bool]$previous.record.publication_authorized) {
    throw '[mir42-nine-programme-superseded-state]'
  }
  Assert-MIR42SealTargetSet -Rows @($previous.record.selected_targets | ForEach-Object { [pscustomobject]@{target=[string]$_} }) -Code 'mir42-nine-programme-superseded'
  $direct = $previous.record.direct_predecessor_authority
  $modern = Get-MIR42DirectPredecessorAuthority -RepoRoot $repo -Reference ([pscustomobject][ordered]@{
    path=(Resolve-MIR42SealContainedArtifactPath -Root $repo -RelativePath ([string]$direct.path) -Code 'mir42-nine-programme-modern-authority')
    sha256=[string]$direct.sha256;record_sha256=[string]$direct.record_sha256
  })
  $predecessors = [Collections.Generic.List[object]]::new()
  foreach ($row in @($modern.record.targets)) {
    $predecessors.Add([pscustomobject][ordered]@{
      target=[string]$row.target;version=[string]$row.predecessor.version;sha256=[string]$row.predecessor.sha256
      engine=[pscustomobject][ordered]@{file_version=[string]$row.engine.file_version;product_version=[string]$row.engine.product_version;sha256=[string]$row.engine.sha256}
    })
  }
  $historical = [Collections.Generic.List[object]]::new()
  foreach ($target in $script:MIR42SealHistoricalTargets) {
    $authority = Get-MIR42HistoricalTerminalAuthority -RepoRoot $repo -Target $target
    $record = $authority.target_record.record
    $historical.Add([pscustomobject][ordered]@{
      target=$target
      target_record=[pscustomobject][ordered]@{path=[string]$authority.identity.target_record_path;sha256=[string]$authority.target_record.sha256;record_sha256=[string]$record.record_sha256}
      terminal_seal=[pscustomobject][ordered]@{path=('.mir/releases/terminal/seals/' + [string]$record.predecessor.version + '.json');sha256=[string]$authority.terminal_seal.sha256;record_sha256=[string]$authority.terminal_seal.record.record_sha256}
    })
    $predecessors.Add([pscustomobject][ordered]@{
      target=$target;version=[string]$record.predecessor.version;sha256=[string]$record.predecessor.sha256
      engine=[pscustomobject][ordered]@{file_version=[string]$record.engine.version;product_version=[string]$record.engine.version;sha256=[string]$record.engine.sha256}
    })
  }
  Assert-MIR42SealTargetSet -Rows @($predecessors) -Scope 'nine-target' -Code 'mir42-nine-programme-predecessors'
  $programme = [pscustomobject][ordered]@{
    schema=1;kind='MIR42NineTargetReleaseCutProgrammeV1'
    status='active-current-4.2-release-cut-pre-freeze-no-transition-authority'
    release_line='4.2';selected_targets=@($script:MIR42SealNineTargetCandidates)
    candidate=[pscustomobject][ordered]@{version_line='4.2';state='unallocated';exact_candidate_required=$true}
    supersedes=[pscustomobject][ordered]@{path=$previousRelative;sha256=[string]$previous.sha256;record_sha256=[string]$previous.record.record_sha256}
    direct_predecessor_authority=$direct
    historical_predecessor_authorities=@($historical)
    direct_predecessors=@($predecessors)
    required_gates=@(foreach ($gate in @($previous.record.required_gates)) {
      $pendingState = switch ([string]$gate.id) {
        'exact-candidate-allocation' { 'not-authorized' }
        'protected-signing-and-recovery' { 'blocked-human' }
        default { 'not-performed' }
      }
      [pscustomobject][ordered]@{id=[string]$gate.id;state=$pendingState;scope='nine-target-release-cut'}
    })
    transition_gate=[pscustomobject][ordered]@{source_freeze=$false;candidate_allocation=$false;production_signing=$false;technical_seal=$false;promotion=$false;tagging=$false;publication=$false}
    release_transition_authority=$false;publication_authorized=$false;record_sha256=''
  }
  # Preparation is create-only or an identical readback. An advanced gate or
  # changed provenance cannot be reset merely because transition flags are false.
  if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
    $existing = Read-MIR42SealRecord -Path $OutputPath -Code 'mir42-nine-programme-existing'
    $expected = ConvertTo-MIR4BootstrapCanonicalJson -Value $programme | ConvertFrom-Json -Depth 100 -DateKind String
    $expected.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $expected
    if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $existing.record) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $expected)) {
      if ($RefreshPendingAuthority -and (Test-MIR42NineTargetPendingAuthorityRefresh -Existing $existing.record -Expected $expected)) {
        if ([string]::IsNullOrWhiteSpace($CheckpointRoot)) { throw '[mir42-nine-programme-pending-refresh-checkpoint-required]' }
        return (Write-MIR42NineTargetPendingAuthorityRefresh -RepoRoot $repo -Record $expected -OutputPath $OutputPath -CheckpointRoot $CheckpointRoot).record
      }
      throw '[mir42-nine-programme-existing-authority-preserved]'
    }
    return $existing.record
  }
  Write-MIR42NormalizedRecord -Record $programme -OutputPath $OutputPath -Code 'mir42-nine-programme-output'
}

function Test-MIR42NineTargetPendingAuthorityRefresh {
  param([Parameter(Mandatory)]$Existing,[Parameter(Mandatory)]$Expected)
  # This refresh is deliberately narrower than a release transition: it may
  # replace only the file/record fingerprints of the five historical target
  # records after their canonical inputs changed.  Every other pending
  # authority field, including all gates and predecessor bindings, must
  # already be byte-for-byte equivalent to the current construction.
  if ($Existing.PSObject.Properties.Name -contains 'written_transition_authorization' -or
      [string]$Existing.status -cne 'active-current-4.2-release-cut-pre-freeze-no-transition-authority' -or
      [string]$Existing.candidate.state -cne 'unallocated' -or
      [bool]$Existing.release_transition_authority -or [bool]$Existing.publication_authorized -or
      @($Existing.transition_gate.PSObject.Properties | Where-Object { $_.Value -isnot [bool] -or [bool]$_.Value }).Count -ne 0) {
    return $false
  }
  $candidate = ConvertTo-MIR4BootstrapCanonicalJson -Value $Existing | ConvertFrom-Json -Depth 100 -DateKind String
  $expectedHistorical = @($Expected.historical_predecessor_authorities)
  $candidateHistorical = @($candidate.historical_predecessor_authorities)
  if ($candidateHistorical.Count -ne $expectedHistorical.Count -or $candidateHistorical.Count -ne $script:MIR42SealHistoricalTargets.Count) { return $false }
  for ($index = 0; $index -lt $candidateHistorical.Count; $index++) {
    $old = $candidateHistorical[$index]
    $current = $expectedHistorical[$index]
    if ([string]$old.target -cne [string]$current.target -or
        [string]$old.target_record.path -cne [string]$current.target_record.path -or
        [string]$old.target_record.sha256 -notmatch '^[A-F0-9]{64}$' -or
        [string]$old.target_record.record_sha256 -notmatch '^[A-F0-9]{64}$') {
      return $false
    }
    $old.target_record.sha256 = [string]$current.target_record.sha256
    $old.target_record.record_sha256 = [string]$current.target_record.record_sha256
  }
  $candidate.record_sha256 = [string]$Expected.record_sha256
  return (ConvertTo-MIR4BootstrapCanonicalJson -Value $candidate) -ceq (ConvertTo-MIR4BootstrapCanonicalJson -Value $Expected)
}

function Write-MIR42NineTargetPendingAuthorityRefresh {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Record,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$CheckpointRoot
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $output = [IO.Path]::GetFullPath($OutputPath)
  $expectedOutput = [IO.Path]::GetFullPath((Join-Path $repo (Get-MIR42SealScopeContract -Scope 'nine-target').programme_path))
  $buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
  $checkpoint = [IO.Path]::GetFullPath($CheckpointRoot)
  if (-not $output.Equals($expectedOutput,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-nine-programme-pending-refresh-output-path]' }
  if (-not $checkpoint.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-nine-programme-pending-refresh-checkpoint-containment]' }
  $old = Read-MIR42SealRecord -Path $output -Code 'mir42-nine-programme-pending-refresh-existing'
  if (-not (Test-MIR42NineTargetPendingAuthorityRefresh -Existing $old.record -Expected $Record)) { throw '[mir42-nine-programme-pending-refresh-authority]' }
  $oldSha = [string]$old.sha256
  $checkpointPath = Join-Path $checkpoint (([IO.Path]::GetFileNameWithoutExtension($output)) + '-before-pending-authority-refresh-' + $oldSha + '.json')
  if (-not (Test-Path -LiteralPath $checkpointPath -PathType Leaf)) {
    New-Item -ItemType Directory -Force -Path $checkpoint | Out-Null
    [IO.File]::Copy($output,$checkpointPath,$false)
  }
  if ((Get-FileHash -LiteralPath $checkpointPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne $oldSha) { throw '[mir42-nine-programme-pending-refresh-checkpoint-hash]' }
  $temporary = Join-Path (Split-Path -Parent $output) (([IO.Path]::GetFileName($output)) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
  $backup = $temporary + '.bak'
  try {
    Write-MIR42NormalizedRecord -Record $Record -OutputPath $temporary -Code 'mir42-nine-programme-pending-refresh-output' | Out-Null
    [IO.File]::Replace($temporary,$output,$backup)
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    if (Test-Path -LiteralPath $backup -PathType Leaf) { Remove-Item -LiteralPath $backup -Force }
  }
  $written = Read-MIR42SealRecord -Path $output -Code 'mir42-nine-programme-pending-refresh-readback'
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $written.record) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $Record)) { throw '[mir42-nine-programme-pending-refresh-readback]' }
  return [pscustomobject][ordered]@{record=$written.record;checkpoint_path=$checkpointPath;checkpoint_sha256=$oldSha}
}

function Read-MIR42NineTargetProgrammeWrittenAuthorization {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Get-Command Read-MIR42NineTargetWrittenReleaseAuthorization -ErrorAction SilentlyContinue)) {
    . (Join-Path $mir42SealRepoRoot 'tools/mir/application/release/readiness/MIR42ReleaseAssets.ps1')
  }
  return Read-MIR42NineTargetWrittenReleaseAuthorization -Path $Path
}

function Resolve-MIR42NineTargetProgrammePath {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$ProgrammePath
  )
  $repo = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
  $build = [IO.Path]::GetFullPath((Join-Path $repo 'build')).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
  $path = if ([IO.Path]::IsPathRooted($ProgrammePath)) { [IO.Path]::GetFullPath($ProgrammePath) } else { [IO.Path]::GetFullPath((Join-Path $repo $ProgrammePath)) }
  if (-not $path.StartsWith($build + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
    throw '[mir42-nine-programme-external-path-containment]'
  }
  $relative = [IO.Path]::GetRelativePath($repo,$path).Replace('\','/')
  if ($relative -match '(^|/)\.\.(/|$)') { throw '[mir42-nine-programme-external-path-containment]' }
  return [pscustomobject][ordered]@{path=$path;relative_path=$relative}
}

function Assert-MIR42NineTargetProgrammeTransitionReference {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Reference)
  Assert-MIR42SealPropertyNames -Value $Reference -Expected @('mode','baseline_programme','maintainer_authorization','candidate_manifest','source','selected_targets','authorized_transition') -Code 'mir42-nine-programme-transition-reference-shape'
  Assert-MIR42SealPropertyNames -Value $Reference.baseline_programme -Expected @('path','sha256','record_sha256') -Code 'mir42-nine-programme-transition-baseline-shape'
  Assert-MIR42SealPropertyNames -Value $Reference.maintainer_authorization -Expected @('path','sha256','record_sha256','recorded_from_user_turn_date') -Code 'mir42-nine-programme-transition-authorization-shape'
  Assert-MIR42SealPropertyNames -Value $Reference.candidate_manifest -Expected @('path','sha256','record_sha256') -Code 'mir42-nine-programme-transition-candidate-shape'
  Assert-MIR42SealPropertyNames -Value $Reference.source -Expected @('commit','tree','package_source_sha256') -Code 'mir42-nine-programme-transition-source-shape'
  Assert-MIR42SealPropertyNames -Value $Reference.authorized_transition -Expected @('source_freeze','candidate_allocation','production_signing','technical_seal','promotion','tagging','publication') -Code 'mir42-nine-programme-transition-gate-shape'
  if ([string]$Reference.mode -cne 'written-conditional-maintainer-go' -or
      ($Reference.selected_targets -join '|') -cne ($script:MIR42SealNineTargetCandidates -join '|') -or
      [string]$Reference.baseline_programme.path -cne (Get-MIR42SealScopeContract -Scope 'nine-target').programme_path -or
      [string]$Reference.baseline_programme.sha256 -notmatch '^[A-F0-9]{64}$' -or
      [string]$Reference.baseline_programme.record_sha256 -notmatch '^[A-F0-9]{64}$' -or
      [string]$Reference.maintainer_authorization.sha256 -notmatch '^[A-F0-9]{64}$' -or
      [string]$Reference.maintainer_authorization.record_sha256 -notmatch '^[A-F0-9]{64}$' -or
      [string]$Reference.candidate_manifest.sha256 -notmatch '^[A-F0-9]{64}$' -or
      [string]$Reference.candidate_manifest.record_sha256 -notmatch '^[A-F0-9]{64}$' -or
      @($Reference.authorized_transition.PSObject.Properties | Where-Object { $_.Value -isnot [bool] }).Count -ne 0 -or
      -not [bool]$Reference.authorized_transition.source_freeze -or -not [bool]$Reference.authorized_transition.candidate_allocation -or
      -not [bool]$Reference.authorized_transition.production_signing -or [bool]$Reference.authorized_transition.technical_seal -or
      [bool]$Reference.authorized_transition.promotion -or [bool]$Reference.authorized_transition.tagging -or [bool]$Reference.authorized_transition.publication) {
    throw '[mir42-nine-programme-transition-reference-state]'
  }
  $baseline = Get-MIR42LiveProgrammeTransition -RepoRoot $RepoRoot -Scope 'nine-target' -AllowPendingTransition
  if ($baseline.record.PSObject.Properties.Name -contains 'written_transition_authorization' -or
      [string]$baseline.sha256 -cne [string]$Reference.baseline_programme.sha256 -or
      [string]$baseline.record.record_sha256 -cne [string]$Reference.baseline_programme.record_sha256) {
    throw '[mir42-nine-programme-transition-baseline-binding]'
  }
  $authorization = Read-MIR42NineTargetProgrammeWrittenAuthorization -Path ([string]$Reference.maintainer_authorization.path)
  if ([string]$authorization.sha256 -cne [string]$Reference.maintainer_authorization.sha256 -or
      [string]$authorization.record.record_sha256 -cne [string]$Reference.maintainer_authorization.record_sha256 -or
      [string]$authorization.record.recorded_from_user_turn_date -cne [string]$Reference.maintainer_authorization.recorded_from_user_turn_date) {
    throw '[mir42-nine-programme-transition-authorization-binding]'
  }
  $candidate = Get-MIR42ExactFourTargetCandidate -RepoRoot $RepoRoot -CandidateManifestPath ([string]$Reference.candidate_manifest.path)
  if ([string]$candidate.scope -cne 'nine-target' -or [string]$candidate.identity.sha256 -cne [string]$Reference.candidate_manifest.sha256 -or
      [string]$candidate.identity.record.record_sha256 -cne [string]$Reference.candidate_manifest.record_sha256 -or
      [string]$candidate.source.commit -cne [string]$Reference.source.commit -or [string]$candidate.source.tree -cne [string]$Reference.source.tree -or
      [string]$candidate.source.package_source_sha256 -cne [string]$Reference.source.package_source_sha256) {
    throw '[mir42-nine-programme-transition-candidate-binding]'
  }
  return [pscustomobject][ordered]@{authorization=$authorization;candidate=$candidate;reference=$Reference}
}

function Assert-MIR42NineTargetProgrammeCandidateBinding {
  param([Parameter(Mandatory)]$Programme,[Parameter(Mandatory)]$Candidate)
  if ($Programme.record.PSObject.Properties.Name -notcontains 'written_transition_authorization') { throw '[mir42-nine-programme-transition-reference-missing]' }
  $binding = $Programme.record.written_transition_authorization.candidate_manifest
  if ([string]$Candidate.scope -cne 'nine-target' -or [string]$binding.sha256 -cne [string]$Candidate.identity.sha256 -or
      [string]$binding.record_sha256 -cne [string]$Candidate.identity.record.record_sha256 -or
      [string]$Programme.record.written_transition_authorization.source.commit -cne [string]$Candidate.source.commit -or
      [string]$Programme.record.written_transition_authorization.source.tree -cne [string]$Candidate.source.tree -or
      [string]$Programme.record.written_transition_authorization.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256) {
    throw '[mir42-nine-programme-transition-readiness-candidate-binding]'
  }
}

function Write-MIR42NineTargetProgrammeAdvance {
  param(
    [Parameter(Mandatory)]$Record,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$BaselinePath,
    [Parameter(Mandatory)][string]$CheckpointRoot
  )
  $output = [IO.Path]::GetFullPath($OutputPath)
  $baseline = [IO.Path]::GetFullPath($BaselinePath)
  $checkpointRoot = [IO.Path]::GetFullPath($CheckpointRoot)
  if (-not (Test-Path -LiteralPath $baseline -PathType Leaf)) { throw '[mir42-nine-programme-advance-baseline-required]' }
  if (-not (Test-Path -LiteralPath (Split-Path -Parent $output) -PathType Container)) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null }
  $oldPath = if (Test-Path -LiteralPath $output -PathType Leaf) { $output } else { $baseline }
  $oldSha = (Get-FileHash -LiteralPath $oldPath -Algorithm SHA256).Hash.ToUpperInvariant()
  $baselineSha = (Get-FileHash -LiteralPath $baseline -Algorithm SHA256).Hash.ToUpperInvariant()
  if ($oldSha -cne $baselineSha) { throw '[mir42-nine-programme-advance-output-state]' }
  $checkpoint = Join-Path $checkpointRoot (([IO.Path]::GetFileNameWithoutExtension($output)) + '-before-written-go-' + $oldSha + '.json')
  if (-not (Test-Path -LiteralPath $checkpoint -PathType Leaf)) {
    New-Item -ItemType Directory -Force -Path $checkpointRoot | Out-Null
    [IO.File]::Copy($oldPath,$checkpoint,$false)
  }
  if ((Get-FileHash -LiteralPath $checkpoint -Algorithm SHA256).Hash.ToUpperInvariant() -cne $oldSha) { throw '[mir42-nine-programme-advance-checkpoint-hash]' }
  $temporary = Join-Path (Split-Path -Parent $output) (([IO.Path]::GetFileName($output)) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
  $backup = $temporary + '.bak'
  try {
    Write-MIR42NormalizedRecord -Record $Record -OutputPath $temporary -Code 'mir42-nine-programme-advance-output' | Out-Null
    if (Test-Path -LiteralPath $output -PathType Leaf) {
      [IO.File]::Replace($temporary,$output,$backup)
    } else {
      [IO.File]::Move($temporary,$output)
    }
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    if (Test-Path -LiteralPath $backup -PathType Leaf) { Remove-Item -LiteralPath $backup -Force }
  }
  $written = Read-MIR42SealRecord -Path $output -Code 'mir42-nine-programme-advance-readback'
  return [pscustomobject][ordered]@{programme=$written;checkpoint_path=$checkpoint;checkpoint_sha256=$oldSha}
}

function Advance-MIR42NineTargetReleaseCutProgramme {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$MaintainerAuthorizationPath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$CheckpointRoot
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
  $output = Resolve-MIR42NineTargetProgrammePath -RepoRoot $repo -ProgrammePath $OutputPath
  $checkpoint = [IO.Path]::GetFullPath($CheckpointRoot)
  if (-not $checkpoint.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-nine-programme-advance-checkpoint-containment]' }
  $baseline = Get-MIR42LiveProgrammeTransition -RepoRoot $repo -Scope 'nine-target' -AllowPendingTransition
  $current = if (Test-Path -LiteralPath $output.path -PathType Leaf) {
    Get-MIR42LiveProgrammeTransition -RepoRoot $repo -Scope 'nine-target' -ProgrammePath $output.path -AllowPendingTransition
  } else { $baseline }
  $authorization = Read-MIR42NineTargetProgrammeWrittenAuthorization -Path $MaintainerAuthorizationPath
  $candidate = Get-MIR42ExactFourTargetCandidate -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath
  if ([string]$candidate.scope -cne 'nine-target') { throw '[mir42-nine-programme-advance-candidate-scope]' }
  if ($current.record.PSObject.Properties.Name -contains 'written_transition_authorization') {
    $existing = Assert-MIR42NineTargetProgrammeTransitionReference -RepoRoot $repo -Reference $current.record.written_transition_authorization
    if ([string]$existing.authorization.sha256 -cne [string]$authorization.sha256 -or [string]$existing.candidate.identity.sha256 -cne [string]$candidate.identity.sha256) {
      throw '[mir42-nine-programme-advance-existing-authority-preserved]'
    }
    return [pscustomobject][ordered]@{record=$current.record;path=$current.path;advanced=$false;checkpoint_path='';checkpoint_sha256=''}
  }
  if ([bool]$current.record.transition_gate.source_freeze -or [bool]$current.record.transition_gate.candidate_allocation -or [bool]$current.record.transition_gate.production_signing) {
    throw '[mir42-nine-programme-advance-pending-state]'
  }
  $programme = $current.record | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $programme.status = 'active-current-4.2-release-cut-transition-authorized-awaiting-technical-proof'
  $programme.candidate.state = 'allocated-written-conditional-go-awaiting-technical-proof'
  $programme.required_gates[0].state = 'authorized-to-proceed-bound-to-exact-candidate'
  $programme.required_gates[3].state = 'authorized-to-proceed-existing-custody-required'
  $programme.transition_gate.source_freeze = $true
  $programme.transition_gate.candidate_allocation = $true
  $programme.transition_gate.production_signing = $true
  $programme | Add-Member -NotePropertyName written_transition_authorization -NotePropertyValue ([pscustomobject][ordered]@{
    mode = 'written-conditional-maintainer-go'
    baseline_programme = [ordered]@{path=[string](Get-MIR42SealScopeContract -Scope 'nine-target').programme_path;sha256=[string]$baseline.sha256;record_sha256=[string]$baseline.record.record_sha256}
    maintainer_authorization = [ordered]@{path=(Resolve-Path -LiteralPath $MaintainerAuthorizationPath).Path;sha256=[string]$authorization.sha256;record_sha256=[string]$authorization.record.record_sha256;recorded_from_user_turn_date=[string]$authorization.record.recorded_from_user_turn_date}
    candidate_manifest = [ordered]@{path=(Resolve-Path -LiteralPath $CandidateManifestPath).Path;sha256=[string]$candidate.identity.sha256;record_sha256=[string]$candidate.identity.record.record_sha256}
    source = $candidate.source
    selected_targets = @($candidate.targets | ForEach-Object { [string]$_.target })
    authorized_transition = [ordered]@{source_freeze=$true;candidate_allocation=$true;production_signing=$true;technical_seal=$false;promotion=$false;tagging=$false;publication=$false}
  })
  $written = Write-MIR42NineTargetProgrammeAdvance -Record $programme -OutputPath $output.path -BaselinePath (Join-Path $repo (Get-MIR42SealScopeContract -Scope 'nine-target').programme_path) -CheckpointRoot $checkpoint
  $verified = Get-MIR42LiveProgrammeTransition -RepoRoot $repo -Scope 'nine-target' -ProgrammePath $output.path
  Assert-MIR42NineTargetProgrammeCandidateBinding -Programme $verified -Candidate $candidate
  return [pscustomobject][ordered]@{record=$verified.record;path=$verified.path;advanced=$true;checkpoint_path=$written.checkpoint_path;checkpoint_sha256=$written.checkpoint_sha256}
}

function Get-MIR42LiveProgrammeTransition {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [ValidateSet('four-target','nine-target')][string]$Scope = 'four-target',
    [AllowEmptyString()][string]$ProgrammePath='',
    [switch]$AllowPendingTransition
  )
  $contract = Get-MIR42SealScopeContract -Scope $Scope
  $relative = [string]$contract.programme_path
  $path = Join-Path $RepoRoot $relative
  if (-not [string]::IsNullOrWhiteSpace($ProgrammePath)) {
    if ($Scope -cne 'nine-target') { throw '[mir42-nine-programme-external-scope]' }
    $external = Resolve-MIR42NineTargetProgrammePath -RepoRoot $RepoRoot -ProgrammePath $ProgrammePath
    $path = $external.path
    $relative = $external.relative_path
  }
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw '[mir42-seal-current-programme-missing]' }
  if ($Scope -ceq 'nine-target') {
    $schemaPath = Join-Path $RepoRoot 'spec/schemas/mir42-nine-target-release-cut-programme-v1.schema.json'
    try {
      if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf) -or -not (Get-Content -Raw -LiteralPath $path | Test-Json -SchemaFile $schemaPath)) {
        throw '[mir42-seal-current-programme-schema]'
      }
    } catch { throw '[mir42-seal-current-programme-schema]' }
  }
  $programmeReceipt = Read-MIR42SealRecord -Path $path -Code 'mir42-seal-current-programme'
  $programme = $programmeReceipt.record
  $programmeProperties = @('schema','kind','status','release_line','selected_targets','candidate','direct_predecessor_authority','direct_predecessors','required_gates','transition_gate','release_transition_authority','publication_authorized','record_sha256')
  if ($Scope -ceq 'nine-target') { $programmeProperties += @('supersedes','historical_predecessor_authorities') }
  $advancedWrittenTransition = ($Scope -ceq 'nine-target' -and $programme.PSObject.Properties.Name -contains 'written_transition_authorization')
  if ($advancedWrittenTransition) { $programmeProperties += 'written_transition_authorization' }
  Assert-MIR42SealPropertyNames -Value $programme -Expected $programmeProperties -Code 'mir42-seal-current-programme-shape'
  Assert-MIR42SealPropertyNames -Value $programme.candidate -Expected @('version_line','state','exact_candidate_required') -Code 'mir42-seal-current-programme-candidate-shape'
  Assert-MIR42SealPropertyNames -Value $programme.direct_predecessor_authority -Expected @('path','kind','record_sha256','sha256') -Code 'mir42-seal-current-programme-predecessor-authority-shape'
  Assert-MIR42SealPropertyNames -Value $programme.transition_gate -Expected @('source_freeze','candidate_allocation','production_signing','technical_seal','promotion','tagging','publication') -Code 'mir42-seal-current-programme-transition-shape'
  if ($Scope -ceq 'nine-target' -and @($programme.transition_gate.PSObject.Properties | Where-Object { $_.Value -isnot [bool] }).Count -ne 0) {
    throw '[mir42-seal-current-programme-transition-type]'
  }
  if ([int]$programme.schema -ne 1 -or [string]$programme.kind -cne [string]$contract.programme_kind -or
      [string]$programme.status -notmatch '^active-current-4[.]2-release-cut-' -or [string]$programme.release_line -cne '4.2' -or
      [string]$programme.candidate.version_line -cne '4.2' -or -not [bool]$programme.candidate.exact_candidate_required -or
      [string]$programme.direct_predecessor_authority.path -cne '.mir/releases/governance/mir4/MIR42-Direct-Predecessor-InputsV1.json' -or
      [string]$programme.direct_predecessor_authority.kind -cne 'MIR42DirectPredecessorInputsV1' -or
      [bool]$programme.release_transition_authority -or [bool]$programme.publication_authorized) {
    throw '[mir42-seal-current-programme-state]'
  }
  Assert-MIR42SealTargetSet -Rows @($programme.selected_targets | ForEach-Object { [pscustomobject]@{target=[string]$_} }) -Code 'mir42-seal-current-programme' -Scope $Scope
  $predecessorAuthority = Get-MIR42DirectPredecessorAuthority -RepoRoot $RepoRoot -Reference ([pscustomobject][ordered]@{
    path = Resolve-MIR42SealContainedArtifactPath -Root $RepoRoot -RelativePath ([string]$programme.direct_predecessor_authority.path) -Code 'mir42-seal-current-programme-predecessor-authority'
    sha256 = [string]$programme.direct_predecessor_authority.sha256
    record_sha256 = [string]$programme.direct_predecessor_authority.record_sha256
  })
  Assert-MIR42SealTargetSet -Rows @($programme.direct_predecessors) -Code 'mir42-seal-current-programme-predecessors' -Scope $Scope
  $historical = @{}
  if ($Scope -ceq 'nine-target') {
    if ($advancedWrittenTransition) {
      if ([string]$programme.status -cne 'active-current-4.2-release-cut-transition-authorized-awaiting-technical-proof' -or
          [string]$programme.candidate.state -cne 'allocated-written-conditional-go-awaiting-technical-proof') {
        throw '[mir42-nine-programme-transition-state]'
      }
      $transitionReference = Assert-MIR42NineTargetProgrammeTransitionReference -RepoRoot $RepoRoot -Reference $programme.written_transition_authorization
      foreach ($field in @('source_freeze','candidate_allocation','production_signing','technical_seal','promotion','tagging','publication')) {
        if ([bool]$programme.transition_gate.$field -ne [bool]$transitionReference.reference.authorized_transition.$field) {
          throw '[mir42-nine-programme-transition-gate-binding]'
        }
      }
    } elseif ([string]$programme.status -ne 'active-current-4.2-release-cut-pre-freeze-no-transition-authority' -or [string]$programme.candidate.state -ne 'unallocated' -or
      @($programme.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
      throw '[mir42-nine-programme-pending-state]'
    }
    $superseded = Read-MIR42SealRecord -Path (Join-Path $RepoRoot (Get-MIR42SealScopeContract -Scope 'four-target').programme_path) -Code 'mir42-seal-current-programme-superseded'
    Assert-MIR42SealPropertyNames -Value $programme.supersedes -Expected @('path','sha256','record_sha256') -Code 'mir42-seal-current-programme-supersedes-shape'
    if ([string]$programme.supersedes.path -cne (Get-MIR42SealScopeContract -Scope 'four-target').programme_path -or
        [string]$programme.supersedes.sha256 -cne [string]$superseded.sha256 -or
        [string]$programme.supersedes.record_sha256 -cne [string]$superseded.record.record_sha256 -or
        [string]$superseded.record.kind -cne 'MIR42ReleaseCutProgrammeV1' -or
        [string]$superseded.record.release_line -cne '4.2' -or
        [bool]$superseded.record.release_transition_authority -or [bool]$superseded.record.publication_authorized) {
      throw '[mir42-seal-current-programme-supersedes-binding]'
    }
    Assert-MIR42SealTargetSet -Rows @($superseded.record.selected_targets | ForEach-Object { [pscustomobject]@{target=[string]$_} }) -Code 'mir42-seal-current-programme-superseded'
    $historicalRows = @($programme.historical_predecessor_authorities)
    if (($historicalRows.target -join '|') -cne ($script:MIR42SealHistoricalTargets -join '|')) { throw '[mir42-seal-current-programme-historical-target-set]' }
    foreach ($binding in $historicalRows) {
      Assert-MIR42SealPropertyNames -Value $binding -Expected @('target','target_record','terminal_seal') -Code 'mir42-seal-current-programme-historical-shape'
      Assert-MIR42SealPropertyNames -Value $binding.target_record -Expected @('path','sha256','record_sha256') -Code 'mir42-seal-current-programme-historical-target-shape'
      Assert-MIR42SealPropertyNames -Value $binding.terminal_seal -Expected @('path','sha256','record_sha256') -Code 'mir42-seal-current-programme-historical-seal-shape'
      $authority = Get-MIR42HistoricalTerminalAuthority -RepoRoot $RepoRoot -Target ([string]$binding.target)
      if ([string]$binding.target_record.path -cne [string]$authority.identity.target_record_path -or
          [string]$binding.target_record.sha256 -cne [string]$authority.target_record.sha256 -or
          [string]$binding.target_record.record_sha256 -cne [string]$authority.target_record.record.record_sha256 -or
          [string]$binding.terminal_seal.path -cne ('.mir/releases/terminal/seals/' + [string]$authority.target_record.record.predecessor.version + '.json') -or
          [string]$binding.terminal_seal.sha256 -cne [string]$authority.terminal_seal.sha256 -or
          [string]$binding.terminal_seal.record_sha256 -cne [string]$authority.terminal_seal.record.record_sha256) {
        throw "[mir42-seal-current-programme-historical-binding] $([string]$binding.target)"
      }
      $historical[[string]$binding.target] = $authority
    }
  }
  foreach ($row in @($programme.direct_predecessors)) {
    Assert-MIR42SealPropertyNames -Value $row -Expected @('target','version','sha256','engine') -Code 'mir42-seal-current-programme-predecessor-shape'
    Assert-MIR42SealPropertyNames -Value $row.engine -Expected @('file_version','product_version','sha256') -Code 'mir42-seal-current-programme-predecessor-engine-shape'
    $authorityRow = if ($historical.ContainsKey([string]$row.target)) {
      $historicalRecord = $historical[[string]$row.target].target_record.record
      @([pscustomobject]@{predecessor=$historicalRecord.predecessor;engine=[pscustomobject]@{file_version=[string]$historicalRecord.engine.version;product_version=[string]$historicalRecord.engine.version;sha256=[string]$historicalRecord.engine.sha256}})
    } else { @($predecessorAuthority.record.targets | Where-Object { [string]$_.target -ceq [string]$row.target }) }
    $authorityRow = @($authorityRow)
    if ($authorityRow.Count -ne 1 -or [string]$row.version -cne [string]$authorityRow[0].predecessor.version -or
        [string]$row.sha256 -cne [string]$authorityRow[0].predecessor.sha256 -or
        [string]$row.engine.file_version -cne [string]$authorityRow[0].engine.file_version -or
        [string]$row.engine.product_version -cne [string]$authorityRow[0].engine.product_version -or
        [string]$row.engine.sha256 -cne [string]$authorityRow[0].engine.sha256) {
      throw "[mir42-seal-current-programme-predecessor-binding] $([string]$row.target)"
    }
  }
  $requiredGateIds = @($programme.required_gates | ForEach-Object { [string]$_.id })
  if (($requiredGateIds -join '|') -cne 'exact-candidate-allocation|joined-real-engine-campaign|independent-acceptance|protected-signing-and-recovery|source-freeze-ledger-authorization|governed-offline-restore|human-go-after-main-readback') {
    throw '[mir42-seal-current-programme-gate-set]'
  }
  foreach ($gate in @($programme.required_gates)) {
    Assert-MIR42SealPropertyNames -Value $gate -Expected @('id','state','scope') -Code 'mir42-seal-current-programme-gate-shape'
    if ([string]$gate.scope -cne ($Scope + '-release-cut')) { throw '[mir42-seal-current-programme-gate-scope]' }
  }
  if ((-not [bool]$programme.transition_gate.source_freeze -or -not [bool]$programme.transition_gate.candidate_allocation -or
      -not [bool]$programme.transition_gate.production_signing) -and -not $AllowPendingTransition) {
    throw '[mir42-seal-current-programme-transition-not-authorized]'
  }
  return [pscustomobject][ordered]@{path=$relative;sha256=$programmeReceipt.sha256;source_freeze_state=[string]$programme.transition_gate.source_freeze;candidate_allocation_state=[string]$programme.transition_gate.candidate_allocation;record=$programme}
}

function Get-MIR42SourceFreezeLedgerPayload {
  param([Parameter(Mandatory)]$Record)
  Assert-MIR42SealPropertyNames -Value $Record -Expected @('schema','kind','status','source','frozen_dev','promotion_base','programme','candidate_manifest','signing_ceremony','independent_reviewer','transition_gate','ledger_signature','record_sha256') -Code 'mir42-seal-freeze-authority-shape'
  Assert-MIR42SealPropertyNames -Value $Record.frozen_dev -Expected @('ref','commit','tree') -Code 'mir42-seal-freeze-frozen-dev-shape'
  Assert-MIR42SealPropertyNames -Value $Record.promotion_base -Expected @('remote','ref','commit') -Code 'mir42-seal-freeze-promotion-base-shape'
  Assert-MIR42SealPropertyNames -Value $Record.programme -Expected @('path','sha256','source_freeze_state','candidate_allocation_state') -Code 'mir42-seal-freeze-programme-shape'
  Assert-MIR42SealPropertyNames -Value $Record.ledger_signature -Expected @('identity','namespace','signature_path','signature_sha256','payload_sha256') -Code 'mir42-seal-freeze-ledger-signature-shape'
  Assert-MIR42SealPropertyNames -Value $Record.independent_reviewer -Expected @('identity','public_key','fingerprint') -Code 'mir42-seal-freeze-reviewer-shape'
  return [pscustomobject][ordered]@{
    schema = [int]$Record.schema
    kind = [string]$Record.kind
    status = [string]$Record.status
    source = $Record.source
    frozen_dev = $Record.frozen_dev
    promotion_base = $Record.promotion_base
    programme = $Record.programme
    candidate_manifest = $Record.candidate_manifest
    signing_ceremony = $Record.signing_ceremony
    independent_reviewer = $Record.independent_reviewer
    transition_gate = $Record.transition_gate
  }
}

function Assert-MIR42SourceFreezeLedgerSignature {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Authority,
    [Parameter(Mandatory)]$Signing,
    [Parameter(Mandatory)][string]$SshKeygenPath
  )
  $record = $Authority.record
  $signature = $record.ledger_signature
  $payload = ConvertTo-MIR4BootstrapCanonicalJson -Value (Get-MIR42SourceFreezeLedgerPayload -Record $record)
  $payloadSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payload)))
  if ([string]$signature.identity -cne [string]$Signing.ledger_signer.principal -or
      [string]$signature.namespace -cne 'mir4-ledger' -or
      [string]$signature.payload_sha256 -cne $payloadSha -or
      [string]$signature.signature_sha256 -notmatch '^[A-F0-9]{64}$' -or
      -not [IO.Path]::IsPathRooted([string]$signature.signature_path)) {
    throw '[mir42-seal-freeze-ledger-signature-binding]'
  }
  $signaturePath = [IO.Path]::GetFullPath([string]$signature.signature_path)
  $repo = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
  if ($signaturePath.StartsWith($repo + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-Path -LiteralPath $signaturePath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $signaturePath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$signature.signature_sha256) {
    throw '[mir42-seal-freeze-ledger-signature-path]'
  }
  $scratchRoot = Assert-MIR4NoReparseAncestors -Root $RepoRoot -Path (Join-Path $RepoRoot 'build/tmp')
  if (-not (Test-Path -LiteralPath $scratchRoot -PathType Container)) { New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null }
  $scratch = Assert-MIR4NoReparseAncestors -Root $scratchRoot -Path (Join-Path $scratchRoot ('mir42-ledger-signature-' + [guid]::NewGuid().ToString('N')))
  try {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    $publicKey = Join-Path $scratch 'ledger-signing.pub'
    $payloadPath = Join-Path $scratch 'source-freeze-payload.json'
    [IO.File]::WriteAllText($publicKey, ([string]$Signing.ledger_signer.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($payloadPath, $payload, [Text.UTF8Encoding]::new($false))
    if (-not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKey -Identity ([string]$Signing.ledger_signer.principal) -Namespace 'mir4-ledger' -PayloadPath $payloadPath -SignaturePath $signaturePath -ScratchRoot (Join-Path $scratch 'verify'))) {
      throw '[mir42-seal-freeze-ledger-signature-verification]'
    }
  } finally {
    if (Test-Path -LiteralPath $scratch) { Remove-MIR4BuildTree -OutputRoot $scratchRoot -Path $scratch }
  }
}

function Get-MIR42SourceFreezeAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Signing,[Parameter(Mandatory)][string]$SshKeygenPath,[AllowEmptyString()][string]$ProgrammePath='')
  $authority = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-freeze'
  $record = $authority.record
  $null = Get-MIR42SourceFreezeLedgerPayload -Record $record
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42SourceFreezeAuthorizationV1' -or
      [string]$record.status -cne 'MIR-4.2-SOURCE-FROZEN-AND-CANDIDATE-ALLOCATED' -or
      [string]$record.signing_ceremony.sha256 -cne [string]$Signing.sha256 -or
      [string]$record.signing_ceremony.record_sha256 -cne [string]$Signing.record.record_sha256 -or
      -not [bool]$record.transition_gate.source_freeze -or -not [bool]$record.transition_gate.candidate_allocation -or
      -not [bool]$record.transition_gate.production_signing -or [bool]$record.transition_gate.technical_seal) {
    throw '[mir42-seal-freeze-authority-state]'
  }
  if ([string]$record.candidate_manifest.sha256 -cne [string]$Candidate.identity.sha256 -or
      [string]$record.candidate_manifest.record_sha256 -cne [string]$Candidate.identity.record.record_sha256 -or
      [string]$record.source.commit -cne [string]$Candidate.source.commit -or
      [string]$record.source.tree -cne [string]$Candidate.source.tree -or
      [string]$record.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256) {
    throw '[mir42-seal-freeze-authority-binding]'
  }
  if ([string]$record.frozen_dev.ref -cne 'refs/heads/dev' -or
      [string]$record.frozen_dev.commit -cne [string]$Candidate.source.commit -or
      [string]$record.frozen_dev.tree -cne [string]$Candidate.source.tree -or
      [string]$record.promotion_base.remote -cne 'origin' -or
      [string]$record.promotion_base.ref -cne 'refs/heads/main' -or
      [string]$record.promotion_base.commit -notmatch '^[0-9a-f]{40}$') {
    throw '[mir42-seal-freeze-promotion-topology-binding]'
  }
  if ([string]$record.independent_reviewer.identity -cne [string]$Signing.independent_reviewer.identity -or
      [string]$record.independent_reviewer.public_key -cne [string]$Signing.independent_reviewer.public_key -or
      [string]$record.independent_reviewer.fingerprint -cne [string]$Signing.independent_reviewer.fingerprint) {
    throw '[mir42-seal-freeze-reviewer-trust-binding]'
  }
  Assert-MIR42SourceFreezeLedgerSignature -RepoRoot $RepoRoot -Authority $authority -Signing $Signing -SshKeygenPath $SshKeygenPath
  $scope = Get-MIR42SealCandidateScope -Candidate $Candidate -Code 'mir42-seal-freeze-candidate'
  $programmeArguments = @{RepoRoot=$RepoRoot;Scope=$scope}
  if (-not [string]::IsNullOrWhiteSpace($ProgrammePath)) { $programmeArguments.ProgrammePath = $ProgrammePath }
  $programme = Get-MIR42LiveProgrammeTransition @programmeArguments
  if ($scope -ceq 'nine-target') { Assert-MIR42NineTargetProgrammeCandidateBinding -Programme $programme -Candidate $Candidate }
  if ([string]$record.programme.path -cne [string]$programme.path -or [string]$record.programme.sha256 -cne [string]$programme.sha256 -or
      [string]$record.programme.source_freeze_state -cne [string]$programme.source_freeze_state -or [string]$record.programme.candidate_allocation_state -cne [string]$programme.candidate_allocation_state) {
    throw '[mir42-seal-freeze-programme-binding]'
  }
  return $authority
}

function Get-MIR42IndependentReviewerAttestation {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Independent,
    [Parameter(Mandatory)]$Campaign,
    [Parameter(Mandatory)]$Freeze,
    [Parameter(Mandatory)][string]$SshKeygenPath
  )
  $attestation = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-reviewer'
  $record = $attestation.record
  Assert-MIR42SealPropertyNames -Value $record -Expected @('schema','kind','status','independent_verification','real_engine_campaign','source_freeze_authority','acceptance_coverage','reviewer','review_signature','record_sha256') -Code 'mir42-seal-reviewer-shape'
  Assert-MIR42SealPropertyNames -Value $record.reviewer -Expected @('identity','public_key','fingerprint') -Code 'mir42-seal-reviewer-identity-shape'
  Assert-MIR42SealPropertyNames -Value $record.review_signature -Expected @('namespace','signature_path','signature_sha256','payload_sha256') -Code 'mir42-seal-reviewer-signature-shape'
  $trusted = $Freeze.record.independent_reviewer
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42IndependentReviewerAttestationV1' -or
      [string]$record.status -cne 'MIR-4.2-INDEPENDENT-REVIEW-ACCEPTED' -or
      [string]$record.independent_verification.sha256 -cne [string]$Independent.sha256 -or
      [string]$record.independent_verification.record_sha256 -cne [string]$Independent.record.record_sha256 -or
      [string]$record.real_engine_campaign.sha256 -cne [string]$Campaign.sha256 -or
      [string]$record.real_engine_campaign.record_sha256 -cne [string]$Campaign.record.record_sha256 -or
      [string]$record.source_freeze_authority.sha256 -cne [string]$Freeze.sha256 -or
      [string]$record.source_freeze_authority.record_sha256 -cne [string]$Freeze.record.record_sha256 -or
      [string]$record.reviewer.identity -cne [string]$trusted.identity -or
      [string]$record.reviewer.public_key -cne [string]$trusted.public_key -or
      [string]$record.reviewer.fingerprint -cne [string]$trusted.fingerprint -or
      [string]$record.review_signature.namespace -cne 'mir4-independent-review' -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $record.acceptance_coverage) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $Campaign.record.release_acceptance) -or
      [string]$record.review_signature.signature_sha256 -notmatch '^[A-F0-9]{64}$') {
    throw '[mir42-seal-reviewer-binding]'
  }
  $payload = [pscustomobject][ordered]@{
    schema = [int]$record.schema
    kind = [string]$record.kind
    status = [string]$record.status
    independent_verification = $record.independent_verification
    real_engine_campaign = $record.real_engine_campaign
    source_freeze_authority = $record.source_freeze_authority
    acceptance_coverage = $record.acceptance_coverage
    reviewer = $record.reviewer
  }
  $payloadJson = ConvertTo-MIR4BootstrapCanonicalJson -Value $payload
  $payloadSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payloadJson)))
  $signaturePath = [string]$record.review_signature.signature_path
  if ([string]$record.review_signature.payload_sha256 -cne $payloadSha -or -not [IO.Path]::IsPathRooted($signaturePath)) {
    throw '[mir42-seal-reviewer-signature-path]'
  }
  $signaturePath = [IO.Path]::GetFullPath($signaturePath)
  $repo = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
  if ($signaturePath.StartsWith($repo + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-Path -LiteralPath $signaturePath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $signaturePath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$record.review_signature.signature_sha256) {
    throw '[mir42-seal-reviewer-signature-path]'
  }
  $scratchRoot = Assert-MIR4NoReparseAncestors -Root $RepoRoot -Path (Join-Path $RepoRoot 'build/tmp')
  if (-not (Test-Path -LiteralPath $scratchRoot -PathType Container)) { New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null }
  $scratch = Assert-MIR4NoReparseAncestors -Root $scratchRoot -Path (Join-Path $scratchRoot ('mir42-review-signature-' + [guid]::NewGuid().ToString('N')))
  try {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    $publicKey = Join-Path $scratch 'reviewer.pub'; $payloadPath = Join-Path $scratch 'review.json'
    [IO.File]::WriteAllText($publicKey, ([string]$trusted.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($payloadPath, $payloadJson, [Text.UTF8Encoding]::new($false))
    if ((Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKey) -cne [string]$trusted.fingerprint -or
        -not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKey -Identity ([string]$trusted.identity) -Namespace 'mir4-independent-review' -PayloadPath $payloadPath -SignaturePath $signaturePath -ScratchRoot (Join-Path $scratch 'verify'))) {
      throw '[mir42-seal-reviewer-signature-verification]'
    }
  } finally {
    if (Test-Path -LiteralPath $scratch) { Remove-MIR4BuildTree -OutputRoot $scratchRoot -Path $scratch }
  }
  return $attestation
}

function Get-MIR42TechnicalSealReadinessForScope {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ValidateSet('four-target','nine-target')][string]$RequiredScope,
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [string]$QualificationPath='',
    [string]$RealEngineCampaignPath='',
    [string]$IndependentVerificationPath='',
    [string]$SigningCeremonyPath='',
    [string]$T16TrustRootPath='',
    [string]$OperatorTrustSourcePath='',
    [string]$T16ProtectedRootPath='',
    [string]$T16ImmutableAnchorPath='',
    [string]$T16ApprovedOwnerSid='',
    [string[]]$T16ApprovedMutationSids=@(),
    [string]$SourceFreezeAuthorityPath='',
    [string]$ReviewerAttestationPath='',
    [string]$SshKeygenPath='',
    [string]$ProgrammePath='',
    [string]$PublishedMaintenancePredecessorManifestPath='',
    [System.Collections.IDictionary]$PublishedMaintenanceArchiveBindings=$null
  )
  $maintenanceRequested = -not [string]::IsNullOrWhiteSpace($PublishedMaintenancePredecessorManifestPath)
  if ($null -ne $PublishedMaintenanceArchiveBindings -and -not $maintenanceRequested) { throw '[mir42-maintenance-readiness-archive-bindings-scope]' }
  if ($maintenanceRequested -and $RequiredScope -cne 'nine-target') { throw '[mir42-maintenance-readiness-candidate-scope]' }
  $maintenanceInputs = $null
  $contract = Get-MIR42SealScopeContract -Scope $RequiredScope
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $checks = [ordered]@{}
  $blockers = [Collections.Generic.List[string]]::new()
  $state = [ordered]@{candidate=$null;programme=$null;qualification=$null;campaign=$null;independent=$null;t16_acl_contract=$null;t16_trust_root=$null;signing=$null;freeze=$null;reviewer=$null}
  try {
    $state.candidate = Get-MIR42ExactFourTargetCandidate -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath
    Assert-MIR42SealTargetSet -Rows @($state.candidate.targets) -Code ("mir42-" + $RequiredScope + '-seal-candidate') -Scope $RequiredScope
    if ($maintenanceRequested) { $contract = Get-MIR42TechnicalSealInputContract -Candidate $state.candidate -PublishedMaintenance }
    $checks.candidate = $true
  } catch { $checks.candidate = $false; $blockers.Add($_.Exception.Message) }
  if ($maintenanceRequested) {
    if ($checks.candidate) {
      try {
        $predecessorContract = Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion $contract.maintenance_source_version
        $metadataText = (& gh api ('repos/Julesc013/more-infinite-research/releases/tags/' + $predecessorContract.source_tag) | Out-String)
        if ($LASTEXITCODE -ne 0) { throw '[mir42-maintenance-readiness-release-readback]' }
        $maintenanceArguments = @{RepoRoot=$repo;ManifestPath=$PublishedMaintenancePredecessorManifestPath
          ReleaseMetadata=($metadataText | ConvertFrom-Json -Depth 100 -DateKind String);CandidateSourceVersion=$contract.maintenance_source_version}
        if ($null -ne $PublishedMaintenanceArchiveBindings) { $maintenanceArguments.ArchiveBindings = $PublishedMaintenanceArchiveBindings }
        $maintenanceInputs = Get-MIR42PublishedMaintenancePredecessorInputs @maintenanceArguments
        $state.maintenance_inputs = $maintenanceInputs
        $checks.maintenance_predecessor = $true
      } catch { $checks.maintenance_predecessor = $false; $blockers.Add($_.Exception.Message) }
    } else { $checks.maintenance_predecessor = $false; $blockers.Add('[mir42-maintenance-readiness-predecessor-unavailable]') }
  }
  if ($checks.candidate) { try { $programmeArguments=@{RepoRoot=$repo;Scope=$RequiredScope};if(-not [string]::IsNullOrWhiteSpace($ProgrammePath)){$programmeArguments.ProgrammePath=$ProgrammePath};$state.programme = Get-MIR42LiveProgrammeTransition @programmeArguments; if ($RequiredScope -ceq 'nine-target') { Assert-MIR42NineTargetProgrammeCandidateBinding -Programme $state.programme -Candidate $state.candidate }; $checks.programme = $true } catch { $checks.programme = $false; $blockers.Add($_.Exception.Message) } } else { $checks.programme = $false; $blockers.Add('[mir42-seal-programme-unavailable]') }
  $candidateInputsReady = $checks.candidate -and (-not $maintenanceRequested -or $checks.maintenance_predecessor)
  if ($candidateInputsReady -and -not [string]::IsNullOrWhiteSpace($QualificationPath)) { try { $state.qualification = Get-MIR42ExactQualificationReceipt -Path $QualificationPath -Candidate $state.candidate -PublishedMaintenanceInputs $maintenanceInputs; $checks.qualification = $true } catch { $checks.qualification = $false; $blockers.Add($_.Exception.Message) } } else { $checks.qualification = $false; $blockers.Add('[mir42-seal-qualification-missing]') }
  if ($checks.qualification -and -not [string]::IsNullOrWhiteSpace($RealEngineCampaignPath)) { try { $state.campaign = Get-MIR42RealEngineCandidateCampaign -RepoRoot $repo -Path $RealEngineCampaignPath -Candidate $state.candidate -Reconciliation $state.qualification -PublishedMaintenanceInputs $maintenanceInputs; $checks.campaign = $true } catch { $checks.campaign = $false; $blockers.Add($_.Exception.Message) } } else { $checks.campaign = $false; $blockers.Add('[mir42-seal-real-engine-campaign-missing]') }
  if ($checks.qualification -and -not [string]::IsNullOrWhiteSpace($IndependentVerificationPath)) { try { $state.independent = Get-MIR42ExactIndependentVerificationReceipt -Path $IndependentVerificationPath -Candidate $state.candidate -Qualification $state.qualification -PublishedMaintenanceInputs $maintenanceInputs; $checks.independent = $true } catch { $checks.independent = $false; $blockers.Add($_.Exception.Message) } } else { $checks.independent = $false; $blockers.Add('[mir42-seal-independent-missing]') }
  if (-not [string]::IsNullOrWhiteSpace($T16ApprovedOwnerSid) -and @($T16ApprovedMutationSids).Count -gt 0) { try { $state.t16_acl_contract = New-MIR42T16AclContract -ApprovedOwnerSid $T16ApprovedOwnerSid -ApprovedMutationSids $T16ApprovedMutationSids; $checks.t16_acl_contract = $true } catch { $checks.t16_acl_contract = $false; $blockers.Add($_.Exception.Message) } } else { $checks.t16_acl_contract = $false; $blockers.Add('[mir42-seal-t16-acl-contract-human-input-required]') }
  if ($checks.t16_acl_contract -and -not [string]::IsNullOrWhiteSpace($T16TrustRootPath) -and -not [string]::IsNullOrWhiteSpace($OperatorTrustSourcePath) -and -not [string]::IsNullOrWhiteSpace($T16ProtectedRootPath) -and -not [string]::IsNullOrWhiteSpace($T16ImmutableAnchorPath) -and -not [string]::IsNullOrWhiteSpace($SshKeygenPath)) { try { $state.t16_trust_root = Get-MIR42ExternalT16LedgerTrustRoot -RepoRoot $repo -T16TrustRootPath $T16TrustRootPath -OperatorTrustSourcePath $OperatorTrustSourcePath -ProtectedRootPath $T16ProtectedRootPath -ImmutableAnchorPath $T16ImmutableAnchorPath -AclContract $state.t16_acl_contract -SshKeygenPath $SshKeygenPath -Scope $RequiredScope; $checks.t16_trust_root = $true } catch { $checks.t16_trust_root = $false; $blockers.Add($_.Exception.Message) } } else { $checks.t16_trust_root = $false; $blockers.Add('[mir42-seal-external-t16-trust-root-or-protected-root-or-immutable-anchor-or-verifier-missing]') }
  if ($checks.t16_trust_root -and -not [string]::IsNullOrWhiteSpace($SigningCeremonyPath)) { try { $state.signing = Get-MIR42ProtectedSigningCeremony -RepoRoot $repo -Path $SigningCeremonyPath -T16TrustRoot $state.t16_trust_root; $checks.signing = $true } catch { $checks.signing = $false; $blockers.Add($_.Exception.Message) } } else { $checks.signing = $false; $blockers.Add('[mir42-seal-signing-or-external-t16-trust-root-missing]') }
  if ($checks.candidate -and $checks.signing -and -not [string]::IsNullOrWhiteSpace($SourceFreezeAuthorityPath) -and -not [string]::IsNullOrWhiteSpace($SshKeygenPath)) { try { $freezeArguments=@{RepoRoot=$repo;Path=$SourceFreezeAuthorityPath;Candidate=$state.candidate;Signing=$state.signing;SshKeygenPath=$SshKeygenPath};if(-not [string]::IsNullOrWhiteSpace($ProgrammePath)){$freezeArguments.ProgrammePath=$ProgrammePath};$state.freeze = Get-MIR42SourceFreezeAuthority @freezeArguments; $checks.freeze = $true } catch { $checks.freeze = $false; $blockers.Add($_.Exception.Message) } } else { $checks.freeze = $false; $blockers.Add('[mir42-seal-freeze-authority-or-verifier-missing]') }
  if ($checks.qualification -and $checks.campaign -and $checks.independent -and $checks.freeze -and -not [string]::IsNullOrWhiteSpace($ReviewerAttestationPath) -and -not [string]::IsNullOrWhiteSpace($SshKeygenPath)) { try { $state.reviewer = Get-MIR42IndependentReviewerAttestation -RepoRoot $repo -Path $ReviewerAttestationPath -Independent $state.independent -Campaign $state.campaign -Freeze $state.freeze -SshKeygenPath $SshKeygenPath; $checks.reviewer = $true } catch { $checks.reviewer = $false; $blockers.Add($_.Exception.Message) } } else { $checks.reviewer = $false; $blockers.Add('[mir42-seal-independent-reviewer-attestation-missing]') }
  $ready = @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value }).Count -eq 0
  return [pscustomobject][ordered]@{
    schema = 1
    kind = [string]$contract.readiness_kind
    status = [string]$contract.readiness_status_prefix + $(if ($ready) { 'READY' } else { 'BLOCKED' })
    checks = [pscustomobject]$checks
    blockers = @($blockers | Select-Object -Unique)
    technical_seal_authorized = $ready
    protected_main_promotion_authorized = $false
    human_go_required_after_main_readback = $true
    tagging_authorized = $false
    publication_authorized = $false
    _state = [pscustomobject]$state
  }
}

function Write-MIR42NormalizedRecord {
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][string]$Code)
  # Ordered dictionaries and PSCustomObjects do not always round-trip to the
  # same canonical representation. Hash the parsed canonical form that will
  # actually be persisted, then prove the written receipt can be read back.
  $normalized = (ConvertTo-MIR4BootstrapCanonicalJson -Value $Record | ConvertFrom-Json -Depth 100 -DateKind String)
  $normalized.record_sha256 = ''
  $normalized.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $normalized
  Write-MIR4BootstrapRecord -Record $normalized -Path $OutputPath | Out-Null
  $readback = Read-MIR42SealRecord -Path $OutputPath -Code $Code
  if (-not (Test-MIR4BootstrapRecordHash -Record $readback.record) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $readback.record) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $normalized)) {
    throw "[$Code-roundtrip]"
  }
  return $readback.record
}

function Get-MIR42FourTargetTechnicalSealReadiness {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [string]$QualificationPath='',
    [string]$RealEngineCampaignPath='',
    [string]$IndependentVerificationPath='',
    [string]$SigningCeremonyPath='',
    [string]$T16TrustRootPath='',
    [string]$OperatorTrustSourcePath='',
    [string]$T16ProtectedRootPath='',
    [string]$T16ImmutableAnchorPath='',
    [string]$T16ApprovedOwnerSid='',
    [string[]]$T16ApprovedMutationSids=@(),
    [string]$SourceFreezeAuthorityPath='',
    [string]$ReviewerAttestationPath='',
    [string]$SshKeygenPath=''
  )
  Get-MIR42TechnicalSealReadinessForScope @PSBoundParameters -RequiredScope 'four-target'
}

function Get-MIR42NineTargetTechnicalSealReadiness {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [string]$QualificationPath='',
    [string]$RealEngineCampaignPath='',
    [string]$IndependentVerificationPath='',
    [string]$SigningCeremonyPath='',
    [string]$T16TrustRootPath='',
    [string]$OperatorTrustSourcePath='',
    [string]$T16ProtectedRootPath='',
    [string]$T16ImmutableAnchorPath='',
    [string]$T16ApprovedOwnerSid='',
    [string[]]$T16ApprovedMutationSids=@(),
    [string]$SourceFreezeAuthorityPath='',
    [string]$ReviewerAttestationPath='',
    [string]$SshKeygenPath='',
    [string]$ProgrammePath='',
    [string]$PublishedMaintenancePredecessorManifestPath='',
    [System.Collections.IDictionary]$PublishedMaintenanceArchiveBindings=$null
  )
  Get-MIR42TechnicalSealReadinessForScope @PSBoundParameters -RequiredScope 'nine-target'
}

function New-MIR42FourTargetTechnicalSeal {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [AllowEmptyString()][string]$QualificationPath='',
    [AllowEmptyString()][string]$RealEngineCampaignPath='',
    [AllowEmptyString()][string]$IndependentVerificationPath='',
    [AllowEmptyString()][string]$SigningCeremonyPath='',
    [AllowEmptyString()][string]$T16TrustRootPath='',
    [AllowEmptyString()][string]$OperatorTrustSourcePath='',
    [AllowEmptyString()][string]$T16ProtectedRootPath='',
    [AllowEmptyString()][string]$T16ImmutableAnchorPath='',
    [AllowEmptyString()][string]$T16ApprovedOwnerSid='',
    [AllowEmptyCollection()][string[]]$T16ApprovedMutationSids=@(),
    [AllowEmptyString()][string]$SourceFreezeAuthorityPath='',
    [AllowEmptyString()][string]$ReviewerAttestationPath='',
    [AllowEmptyString()][string]$SshKeygenPath='',
    [Parameter(Mandatory)][string]$OutputPath
  )
  New-MIR42TechnicalSealForScope @PSBoundParameters -RequiredScope 'four-target'
}

function New-MIR42NineTargetTechnicalSeal {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [AllowEmptyString()][string]$QualificationPath='',
    [AllowEmptyString()][string]$RealEngineCampaignPath='',
    [AllowEmptyString()][string]$IndependentVerificationPath='',
    [AllowEmptyString()][string]$SigningCeremonyPath='',
    [AllowEmptyString()][string]$T16TrustRootPath='',
    [AllowEmptyString()][string]$OperatorTrustSourcePath='',
    [AllowEmptyString()][string]$T16ProtectedRootPath='',
    [AllowEmptyString()][string]$T16ImmutableAnchorPath='',
    [AllowEmptyString()][string]$T16ApprovedOwnerSid='',
    [AllowEmptyCollection()][string[]]$T16ApprovedMutationSids=@(),
    [AllowEmptyString()][string]$SourceFreezeAuthorityPath='',
    [AllowEmptyString()][string]$ReviewerAttestationPath='',
    [AllowEmptyString()][string]$SshKeygenPath='',
    [AllowEmptyString()][string]$ProgrammePath='',
    [AllowEmptyString()][string]$PublishedMaintenancePredecessorManifestPath='',
    [System.Collections.IDictionary]$PublishedMaintenanceArchiveBindings=$null,
    [Parameter(Mandatory)][string]$OutputPath
  )
  New-MIR42TechnicalSealForScope @PSBoundParameters -RequiredScope 'nine-target'
}

function New-MIR42NineTargetRealEngineEvidenceBinder {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$EvidenceReconciliationPath,
    [Parameter(Mandatory)][string]$EngineRunPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$PublishedMaintenancePredecessorManifestPath = '',
    [System.Collections.IDictionary]$PublishedMaintenanceArchiveBindings = $null
  )
  $candidate = Get-MIR42ExactFourTargetCandidate -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath
  Assert-MIR42SealTargetSet -Rows @($candidate.targets) -Scope 'nine-target' -Code 'mir42-nine-target-engine-evidence-candidate'
  New-MIR42FourTargetRealEngineEvidenceBinder @PSBoundParameters
}

function New-MIR42TechnicalSealForScope {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ValidateSet('four-target','nine-target')][string]$RequiredScope,
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [AllowEmptyString()][string]$QualificationPath='',
    [AllowEmptyString()][string]$RealEngineCampaignPath='',
    [AllowEmptyString()][string]$IndependentVerificationPath='',
    [AllowEmptyString()][string]$SigningCeremonyPath='',
    [AllowEmptyString()][string]$T16TrustRootPath='',
    [AllowEmptyString()][string]$OperatorTrustSourcePath='',
    [AllowEmptyString()][string]$T16ProtectedRootPath='',
    [AllowEmptyString()][string]$T16ImmutableAnchorPath='',
    [AllowEmptyString()][string]$T16ApprovedOwnerSid='',
    [AllowEmptyCollection()][string[]]$T16ApprovedMutationSids=@(),
    [AllowEmptyString()][string]$SourceFreezeAuthorityPath='',
    [AllowEmptyString()][string]$ReviewerAttestationPath='',
    [AllowEmptyString()][string]$SshKeygenPath='',
    [AllowEmptyString()][string]$ProgrammePath='',
    [AllowEmptyString()][string]$PublishedMaintenancePredecessorManifestPath='',
    [System.Collections.IDictionary]$PublishedMaintenanceArchiveBindings=$null,
    [Parameter(Mandatory)][string]$OutputPath
  )
  $readiness = Get-MIR42TechnicalSealReadinessForScope -RequiredScope $RequiredScope -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath `
    -QualificationPath $QualificationPath -RealEngineCampaignPath $RealEngineCampaignPath -IndependentVerificationPath $IndependentVerificationPath `
    -SigningCeremonyPath $SigningCeremonyPath -T16TrustRootPath $T16TrustRootPath -OperatorTrustSourcePath $OperatorTrustSourcePath -T16ProtectedRootPath $T16ProtectedRootPath -T16ImmutableAnchorPath $T16ImmutableAnchorPath -T16ApprovedOwnerSid $T16ApprovedOwnerSid -T16ApprovedMutationSids $T16ApprovedMutationSids `
    -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath -ReviewerAttestationPath $ReviewerAttestationPath -SshKeygenPath $SshKeygenPath -ProgrammePath $ProgrammePath `
    -PublishedMaintenancePredecessorManifestPath $PublishedMaintenancePredecessorManifestPath -PublishedMaintenanceArchiveBindings $PublishedMaintenanceArchiveBindings
  if (-not [bool]$readiness.technical_seal_authorized) { throw "[mir42-seal-not-authorized] $($readiness.blockers -join '; ')" }
  $state = $readiness._state
  $maintenanceRequested = -not [string]::IsNullOrWhiteSpace($PublishedMaintenancePredecessorManifestPath)
  $contract = Get-MIR42TechnicalSealInputContract -Candidate $state.candidate -PublishedMaintenance:$maintenanceRequested
  $seal = [pscustomobject][ordered]@{
    schema = 1
    kind = [string]$contract.seal_kind
    status = [string]$contract.seal_status
    source = $state.candidate.source
    candidate_manifest = [ordered]@{sha256=[string]$state.candidate.identity.sha256;record_sha256=[string]$state.candidate.identity.record.record_sha256}
    qualification = [ordered]@{sha256=[string]$state.qualification.sha256;record_sha256=[string]$state.qualification.record.record_sha256}
    real_engine_campaign = [ordered]@{sha256=[string]$state.campaign.sha256;record_sha256=[string]$state.campaign.record.record_sha256}
    independent_verification = [ordered]@{sha256=[string]$state.independent.sha256;record_sha256=[string]$state.independent.record.record_sha256}
    t16_acl_contract = [ordered]@{owner_sid=[string]$state.t16_acl_contract.record.owner_sid;mutation_sids=@($state.t16_acl_contract.record.mutation_sids);custodian_sid_set_sha256=[string]$state.t16_acl_contract.custodian_sid_set_sha256}
    t16_protected_root = [string]$state.t16_trust_root.protected_root
    t16_immutable_anchor = [string]$state.t16_trust_root.immutable_anchor
    t16_ledger_trust_root = [ordered]@{path=[string]$state.t16_trust_root.path;sha256=[string]$state.t16_trust_root.sha256;record_sha256=[string]$state.t16_trust_root.record.record_sha256}
    signing_ceremony = [ordered]@{sha256=[string]$state.signing.sha256;record_sha256=[string]$state.signing.record.record_sha256}
    source_freeze_authority = [ordered]@{sha256=[string]$state.freeze.sha256;record_sha256=[string]$state.freeze.record.record_sha256}
    independent_reviewer_attestation = [ordered]@{sha256=[string]$state.reviewer.sha256;record_sha256=[string]$state.reviewer.record.record_sha256}
    targets = @($state.candidate.targets)
    protected_main_promotion_authorized = $false
    human_go_required_after_main_readback = $true
    tagging_authorized = $false
    publication_authorized = $false
    record_sha256 = ''
  }
  if ($maintenanceRequested) { $seal | Add-Member -NotePropertyName published_maintenance_predecessor -NotePropertyValue $state.maintenance_inputs }
  return (Write-MIR42NormalizedRecord -Record $seal -OutputPath $OutputPath -Code 'mir42-seal-output')
}
