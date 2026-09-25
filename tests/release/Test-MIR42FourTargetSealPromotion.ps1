# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42ProtectedMainPromotion.ps1')

function Assert-MIR42SealTest {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[mir42-seal-test] $Code" }
}

$root = Join-Path $RepoRoot ('build/test-results/mir42-four-target-seal-' + [guid]::NewGuid().ToString('N'))
try {
  $assets = Join-Path $root 'assets'
  $rows = Join-Path $root 'target-rows'
  New-Item -ItemType Directory -Force -Path $assets,$rows | Out-Null
  $source = [ordered]@{
    commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
    tree = (& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
  }
  $packageSource = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot
  $versions = [ordered]@{f210='4.2.21000';f200='4.2.20000';f110='4.2.11000';f100='4.2.10000'}
  $targets = [Collections.Generic.List[object]]::new()
  foreach ($target in @('f210','f200','f110','f100')) {
    $assetRelative = "assets/$target.zip"
    $assetPath = Join-Path $root $assetRelative
    [IO.File]::WriteAllText($assetPath, "synthetic-$target", [Text.UTF8Encoding]::new($false))
    $asset = [ordered]@{path=$assetRelative;bytes=[int64](Get-Item $assetPath).Length;sha256=(Get-FileHash $assetPath -Algorithm SHA256).Hash.ToUpperInvariant()}
    $row = [pscustomobject][ordered]@{
      schema=1;kind='MIR42FourTargetCandidateTargetRowV1';target=$target;distribution_version=$versions[$target]
      asset=$asset;content_sha256=('A' * 64);entry_count=1;build_a_sha256=$asset.sha256;build_b_sha256=$asset.sha256
      deterministic_archive_bytes=$true;package_excluded_surface=$true;record_sha256=''
    }
    $row.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $row
    $rowRelative = "target-rows/$target.json"
    Write-MIR4BootstrapRecord -Record $row -Path (Join-Path $root $rowRelative) | Out-Null
    $targets.Add([pscustomobject][ordered]@{target=$target;distribution_version=$versions[$target];target_row_path=$rowRelative;asset=$asset;content_sha256=('A' * 64);entry_count=1})
  }
  $manifest = [pscustomobject][ordered]@{
    schema=1;kind='MIR42FourTargetCandidateManifestV1';status='private-deterministic-four-target-candidate-built-unqualified';build_complete=$true
    source=[pscustomobject]$source;package_authority_sha256=('B' * 64);package_source_sha256=$packageSource;target_authority=@();resource_admission=@{}
    targets=@($targets);failures=@();qualification='not-performed';technical_seal='not-performed';signing='not-performed';tagging='not-performed';publication_authorized=$false;record_sha256=''
  }
  $manifest.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $manifest
  $manifestPath = Join-Path $root 'candidate-manifest.json'
  Write-MIR4BootstrapRecord -Record $manifest -Path $manifestPath | Out-Null

  $readiness = Get-MIR42FourTargetTechnicalSealReadiness -RepoRoot $RepoRoot -CandidateManifestPath $manifestPath
  Assert-MIR42SealTest ($readiness.status -ceq 'MIR-4.2-FOUR-TARGET-TECHNICAL-SEAL-BLOCKED') 'missing-gates-block-seal'
  Assert-MIR42SealTest ([bool]$readiness.checks.candidate -and -not [bool]$readiness.checks.qualification -and -not [bool]$readiness.technical_seal_authorized) 'candidate-only-readiness'
  $preparation = Join-Path $RepoRoot '.mir/releases/governance/mir4/signing-ceremony-preparation.json'
  $preparedOnly = Get-MIR42FourTargetTechnicalSealReadiness -RepoRoot $RepoRoot -CandidateManifestPath $manifestPath -SigningCeremonyPath $preparation
  Assert-MIR42SealTest (-not [bool]$preparedOnly.checks.signing -and -not [bool]$preparedOnly.technical_seal_authorized) 'preparation-is-not-approved-signer-and-recovery'
  $rejected = $false
  try { New-MIR42FourTargetTechnicalSeal -RepoRoot $RepoRoot -CandidateManifestPath $manifestPath -QualificationPath (Join-Path $root 'missing-qualification.json') -IndependentVerificationPath (Join-Path $root 'missing-independent.json') -SigningCeremonyPath (Join-Path $root 'missing-signing.json') -SourceFreezeAuthorityPath (Join-Path $root 'missing-freeze.json') -OutputPath (Join-Path $root 'seal.json') | Out-Null } catch { $rejected = $_.Exception.Message -match 'mir42-seal-not-authorized'; if (-not $rejected) { throw $_ } }
  Assert-MIR42SealTest $rejected 'seal-cannot-bypass-missing-evidence'

  $seal = [pscustomobject][ordered]@{
    schema=1;kind='MIR42FourTargetTechnicalSealV1';status='MIR-4.2-FOUR-TARGET-TECHNICALLY-SEALED-AWAITING-PROTECTED-MAIN-PR'
    source=[pscustomobject]@{commit=$source.commit;tree=$source.tree;package_source_sha256=$packageSource}
    candidate_manifest=[pscustomobject]@{sha256=(Get-FileHash $manifestPath -Algorithm SHA256).Hash.ToUpperInvariant();record_sha256=$manifest.record_sha256}
    qualification=@{};independent_verification=@{};signing_ceremony=@{};source_freeze_authority=@{};targets=@($targets)
    protected_main_promotion_authorized=$false;human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false;record_sha256=''
  }
  $seal.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $seal
  $sealPath = Join-Path $root 'technical-seal.json'
  Write-MIR4BootstrapRecord -Record $seal -Path $sealPath | Out-Null
  $plan = Get-MIR42ProtectedMainPromotionPlan -RepoRoot $RepoRoot -TechnicalSealPath $sealPath -CandidateManifestPath $manifestPath
  Assert-MIR42SealTest ($plan.status -ceq 'MIR-4.2-PROTECTED-MAIN-PROMOTION-PLAN-ONLY' -and [bool]$plan.pull_request_required -and [bool]$plan.linear_history_required) 'protected-pr-plan'
  Assert-MIR42SealTest (($plan.required_status_checks -join '|') -ceq 'branch-policy|verification-gate' -and $plan.bypass_actors_allowed -eq 0 -and -not [bool]$plan.remote_mutation_performed) 'no-bypass-or-remote-effect'

  $sourceDrift = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $sourceDrift.source.tree = '0' * 40
  $sourceDrift.record_sha256 = ''
  $sourceDrift.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $sourceDrift
  $sourceDriftPath = Join-Path $root 'candidate-source-drift.json'
  Write-MIR4BootstrapRecord -Record $sourceDrift -Path $sourceDriftPath | Out-Null
  $sourceRejected = $false
  try { Get-MIR42ExactFourTargetCandidate -RepoRoot $RepoRoot -CandidateManifestPath $sourceDriftPath | Out-Null } catch { $sourceRejected = $_.Exception.Message -match 'mir42-seal-candidate-source-tree-drift' }
  Assert-MIR42SealTest $sourceRejected 'candidate-tree-drift-rejected'

  [IO.File]::AppendAllText((Join-Path $root 'assets/f210.zip'),'drift',[Text.UTF8Encoding]::new($false))
  $assetRejected = $false
  try { Get-MIR42ExactFourTargetCandidate -RepoRoot $RepoRoot -CandidateManifestPath $manifestPath | Out-Null } catch { $assetRejected = $_.Exception.Message -match 'mir42-seal-candidate-asset-drift' }
  Assert-MIR42SealTest $assetRejected 'candidate-asset-drift-rejected'
  Write-Output 'MIR 4.2 four-target seal and protected-main plan passed candidate identity, missing-evidence, no-bypass, and asset-drift checks; no remote mutation occurred.'
} finally {
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
