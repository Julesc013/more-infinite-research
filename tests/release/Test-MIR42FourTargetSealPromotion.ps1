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

function Set-MIR42SealTestExactAcl {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$OwnerSid)
  $security = if (Test-Path -LiteralPath $Path -PathType Container) { [Security.AccessControl.DirectorySecurity]::new() } else { [Security.AccessControl.FileSecurity]::new() }
  $security.SetOwner([Security.Principal.SecurityIdentifier]$OwnerSid)
  $security.SetAccessRuleProtection($true,$false)
  $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]$OwnerSid,[Security.AccessControl.FileSystemRights]::FullControl,[Security.AccessControl.AccessControlType]::Allow))
  Set-Acl -LiteralPath $Path -AclObject $security
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$root = Join-Path $RepoRoot ('build/test-results/mir42-four-target-seal-' + [guid]::NewGuid().ToString('N'))
$externalForgedTrustRoot = ''
try {
  $assets = Join-Path $root 'assets'
  $rows = Join-Path $root 'target-rows'
  New-Item -ItemType Directory -Force -Path $assets,$rows | Out-Null
  $source = [ordered]@{
    commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
    tree = (& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
  }
  $packageSource = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $targets = [Collections.Generic.List[object]]::new()
  foreach ($target in @('f210','f200','f110','f100')) {
    $identity = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $RepoRoot -Target $target -SourceVersion '4.2.0'
    $assetRelative = "assets/$([string]$identity.package_name)"
    $assetPath = Join-Path $root $assetRelative
    $stage = Join-Path $root "staging/$target/$([string]$identity.distribution_root)"
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    [IO.File]::WriteAllText((Join-Path $stage 'info.json'), (([ordered]@{name='more-infinite-research';version=[string]$identity.distribution_version;factorio_version=([string]$identity.target_id -replace '^factorio-','')} | ConvertTo-Json -Compress)), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $stage 'data.lua'), 'return {}', [Text.UTF8Encoding]::new($false))
    [IO.Compression.ZipFile]::CreateFromDirectory((Split-Path -Parent $stage), $assetPath, [IO.Compression.CompressionLevel]::Optimal, $false)
    $inventory = Get-MIR4ArchiveInventory -Path $assetPath
    $asset = [ordered]@{path=$assetRelative;bytes=[int64]$inventory.bytes;sha256=[string]$inventory.archive_sha256}
    $row = [pscustomobject][ordered]@{
      schema=1;kind='MIR42FourTargetCandidateTargetRowV1';target=$target;distribution_version=[string]$identity.distribution_version
      asset=$asset;content_sha256=[string]$inventory.content_sha256;entry_count=[int]$inventory.entry_count;build_a_sha256=$asset.sha256;build_b_sha256=$asset.sha256
      deterministic_archive_bytes=$true;package_excluded_surface=$true;record_sha256=''
    }
    $row.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $row
    $rowRelative = "target-rows/$target.json"
    Write-MIR4BootstrapRecord -Record $row -Path (Join-Path $root $rowRelative) | Out-Null
    $targets.Add([pscustomobject][ordered]@{target=$target;distribution_version=[string]$identity.distribution_version;target_row_path=$rowRelative;asset=$asset;content_sha256=[string]$inventory.content_sha256;entry_count=[int]$inventory.entry_count})
  }
  $manifest = [pscustomobject][ordered]@{
    schema=1;kind='MIR42FourTargetDeterministicCandidateManifestV1';status='private-deterministic-four-target-candidate-built-unqualified';build_complete=$true
    source=[pscustomobject]$source;package_authority_sha256=('B' * 64);package_source_sha256=$packageSource;target_authority=@();resource_admission=@{}
    targets=@($targets);failures=@();qualification='not-performed';technical_seal='not-performed';signing='not-performed';tagging='not-performed';publication_authorized=$false;record_sha256=''
  }
  $manifest.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $manifest
  $manifestPath = Join-Path $root 'candidate-manifest.json'
  Write-MIR4BootstrapRecord -Record $manifest -Path $manifestPath | Out-Null

  $roundTripProbe = [ordered]@{
    schema=1;kind='MIR42TechnicalSealRoundTripProbeV1'
    nested=[ordered]@{row=[ordered]@{target='f210';values=@([ordered]@{sha256=('A' * 64);entry_count=1})}}
    record_sha256=''
  }
  $roundTripProbePath = Join-Path $root 'technical-seal-roundtrip.json'
  $roundTripSeal = Write-MIR42NormalizedRecord -Record $roundTripProbe -OutputPath $roundTripProbePath -Code 'test-roundtrip'
  Assert-MIR42SealTest (Test-MIR4BootstrapRecordHash -Record $roundTripSeal) 'technical-seal-producer-normalizes-before-hashing'

  $verifierAuthority = [pscustomobject][ordered]@{
    source = [pscustomobject][ordered]@{commit=$source.commit;tree=$source.tree}
    dependencies = @($script:MIR42SealVerifierDependencyPaths | ForEach-Object { [pscustomobject][ordered]@{path=[string]$_;sha256=(Get-FileHash -LiteralPath (Join-Path $RepoRoot $_) -Algorithm SHA256).Hash.ToUpperInvariant()} })
  }
  Assert-MIR42SealExternalVerifierAuthority -RepoRoot $RepoRoot -Verifier $verifierAuthority -Code 'mir42-seal-test-verifier-authority' | Out-Null
  $verifierHashDrift = $verifierAuthority | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 -DateKind String
  $verifierHashDrift.dependencies[0].sha256 = '0' * 64
  $verifierHashRejected = $false
  try { Assert-MIR42SealExternalVerifierAuthority -RepoRoot $RepoRoot -Verifier $verifierHashDrift -Code 'mir42-seal-test-verifier-authority' } catch { $verifierHashRejected = $_.Exception.Message -match 'mir42-seal-test-verifier-authority-dependency-hash' }
  Assert-MIR42SealTest $verifierHashRejected 'external-t16-verifier-dependency-hash-required'

  $dirtyVerifierPath = Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1'
  $dirtyVerifierBytes = [IO.File]::ReadAllBytes($dirtyVerifierPath)
  $dirtyToolsRejected = $false
  try {
    [IO.File]::AppendAllText($dirtyVerifierPath, "`n# MIR42 test-only dirty verifier probe`n", [Text.UTF8Encoding]::new($false))
    try { Assert-MIR42SealSource -RepoRoot $RepoRoot -Source ([pscustomobject]@{commit=$source.commit;tree=$source.tree;package_source_sha256=$packageSource}) -Code 'mir42-seal-test-dirty-tools' | Out-Null } catch { $dirtyToolsRejected = $_.Exception.Message -match 'mir42-seal-test-dirty-tools-source-dirty' }
  } finally {
    [IO.File]::WriteAllBytes($dirtyVerifierPath,$dirtyVerifierBytes)
  }
  Assert-MIR42SealTest $dirtyToolsRejected 'dirty-verifier-tools-rejected'

  $readiness = Get-MIR42FourTargetTechnicalSealReadiness -RepoRoot $RepoRoot -CandidateManifestPath $manifestPath
  Assert-MIR42SealTest ($readiness.status -ceq 'MIR-4.2-FOUR-TARGET-TECHNICAL-SEAL-BLOCKED') 'missing-gates-block-seal'
  Assert-MIR42SealTest ([bool]$readiness.checks.candidate -and -not [bool]$readiness.checks.qualification -and -not [bool]$readiness.checks.campaign -and -not [bool]$readiness.checks.reviewer -and -not [bool]$readiness.technical_seal_authorized) 'candidate-only-readiness'
  Assert-MIR42SealTest (-not [bool]$readiness.checks.t16_acl_contract -and (@($readiness.blockers) -match 'mir42-seal-t16-acl-contract-human-input-required').Count -eq 1) 'human-approved-t16-acl-contract-required'
  Assert-MIR42SealTest (-not [bool]$readiness.checks.t16_trust_root -and (@($readiness.blockers) -match 'mir42-seal-external-t16-trust-root-or-protected-root-or-immutable-anchor-or-verifier-missing').Count -eq 1) 'external-t16-trust-root-required'
  Assert-MIR42SealTest (-not [bool]$readiness.checks.programme -and (@($readiness.blockers) -match 'mir42-seal-current-programme-transition-not-authorized').Count -eq 1) 'current-4-2-release-cut-blocks-unapproved-freeze'
  $containingRootRejected = $false
  try { Resolve-MIR42SealExternalProtectedDirectory -RepoRoot $RepoRoot -Path (Split-Path -Parent $RepoRoot) -Code 'mir42-seal-test-containing-root' | Out-Null } catch { $containingRootRejected = $_.Exception.Message -match 'mir42-seal-test-containing-root-repository' }
  Assert-MIR42SealTest $containingRootRejected 'protected-root-containing-repository-rejected'
  $mislabelledQualification = [pscustomobject][ordered]@{
    schema=1;kind='MIR42FourTargetExactCandidateQualificationV1';status='MIR-4.2-FOUR-TARGET-EXACT-CANDIDATE-QUALIFICATION-PASSED-PRIVATE-UNSEALED'
    factorio_processes=4;release_qualification='claimed';independent_verification='not-performed';publication_authorized=$false;record_sha256=''
  }
  $mislabelledQualification.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $mislabelledQualification
  $mislabelledQualificationPath = Join-Path $root 'mislabelled-qualification.json'
  Write-MIR4BootstrapRecord -Record $mislabelledQualification -Path $mislabelledQualificationPath | Out-Null
  $mislabelledRejected = $false
  try { Get-MIR42ExactQualificationReceipt -Path $mislabelledQualificationPath -Candidate $readiness._state.candidate | Out-Null } catch { $mislabelledRejected = $_.Exception.Message -match 'mir42-seal-evidence-reconciliation-state' }
  Assert-MIR42SealTest $mislabelledRejected 'mislabelled-reconciliation-cannot-be-release-qualification'
  $absoluteRoot = [IO.Path]::GetFullPath($root)
  $fakeRunnerPath = Join-Path $absoluteRoot 'fake-engine-runner.ps1'
  [IO.File]::WriteAllText($fakeRunnerPath, 'Invoke-MIR42FourTargetEngineRun', [Text.UTF8Encoding]::new($false))
  $fakeReconciliation = [pscustomobject]@{sha256=('A' * 64);record=[pscustomobject]@{record_sha256=('B' * 64)}}
  $fakeCampaignTargets = @($readiness._state.candidate.targets | ForEach-Object {
    [pscustomobject][ordered]@{
      target=[string]$_.target;distribution_version=[string]$_.distribution_version
      archive=[pscustomobject]@{sha256=[string]$_.archive_sha256;content_sha256=[string]$_.content_sha256;entry_count=[int]$_.entry_count};status='passed'
      engine_execution=[pscustomobject]@{
        executable_path=(Join-Path $absoluteRoot 'missing-factorio.exe');executable_sha256=('C' * 64);version='1.0.0.0'
        predecessor=[pscustomobject]@{path=(Join-Path $absoluteRoot 'missing-predecessor.zip');sha256=('D' * 64);version='4.0.0.0'}
        harness_receipt=[pscustomobject]@{path=(Join-Path $absoluteRoot 'missing-upgrade.json');sha256=('E' * 64)};harness_exit_code=0
        logs=@([pscustomobject]@{phase='create';path=(Join-Path $absoluteRoot 'missing-create.txt');sha256=('F' * 64)},[pscustomobject]@{phase='load';path=(Join-Path $absoluteRoot 'missing-load.txt');sha256=('F' * 64)},[pscustomobject]@{phase='reload';path=(Join-Path $absoluteRoot 'missing-reload.txt');sha256=('F' * 64)},[pscustomobject]@{phase='second-reload';path=(Join-Path $absoluteRoot 'missing-second-reload.txt');sha256=('F' * 64)})
        fresh_loads=@();fresh_exact_load=$true;predecessor_upgrade=$true;reload_count=2
      }
    }
  })
  $fakeHarnessPath = Join-Path $RepoRoot 'tests/runtime/Test-MIRUpgrade.ps1'
  $fakeEngineRun = [pscustomobject][ordered]@{
    schema=1;kind='MIR42FourTargetEngineRunV1';status='four-target-base-default-real-engine-probes-passed-private-unqualified'
    source=$readiness._state.candidate.source
    candidate_manifest=[pscustomobject]@{path=[IO.Path]::GetFullPath($manifestPath);sha256=(Get-FileHash $manifestPath -Algorithm SHA256).Hash.ToUpperInvariant();record_sha256=$manifest.record_sha256}
    predecessor_authority=[pscustomobject]@{path=(Join-Path $absoluteRoot 'missing-predecessor-authority.json');sha256=('A' * 64);record_sha256=('B' * 64)}
    public_v410_checksum_asset=[pscustomobject]@{release_id=1;asset_id=1;digest=('sha256:' + ('A' * 64).ToLowerInvariant());bytes=412;download_verified=$true}
    runner=[pscustomobject]@{path=$fakeRunnerPath;sha256=(Get-FileHash $fakeRunnerPath -Algorithm SHA256).Hash.ToUpperInvariant()}
    harness=[pscustomobject]@{path=[IO.Path]::GetFullPath($fakeHarnessPath);sha256=(Get-FileHash $fakeHarnessPath -Algorithm SHA256).Hash.ToUpperInvariant()}
    targets=@($fakeCampaignTargets | ForEach-Object {
      $campaignTarget = $_
      $candidateTarget = @($readiness._state.candidate.targets | Where-Object { [string]$_.target -ceq [string]$campaignTarget.target })[0]
      [pscustomobject][ordered]@{target=[string]$campaignTarget.target;status=[string]$campaignTarget.status;archive=[pscustomobject]@{path=[string]$candidateTarget.archive_path;sha256=[string]$campaignTarget.archive.sha256};engine_execution=$campaignTarget.engine_execution}
    });factorio_processes=9;release_qualification='not-performed';publication_authorized=$false;record_sha256=''
  }
  $fakeEngineRun.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $fakeEngineRun
  $fakeEngineRunPath = Join-Path $root 'syntactically-valid-fake-engine-run.json'
  Write-MIR4BootstrapRecord -Record $fakeEngineRun -Path $fakeEngineRunPath | Out-Null
  $fakeCampaign = [pscustomobject][ordered]@{
    schema=1;kind='MIR42FourTargetRealEngineCandidateCampaignV1';status='MIR-4.2-FOUR-TARGET-REAL-ENGINE-CAMPAIGN-PASSED-PRIVATE-UNSEALED';source=$readiness._state.candidate.source
    candidate_manifest=[pscustomobject]@{sha256=$readiness._state.candidate.identity.sha256;record_sha256=$readiness._state.candidate.identity.record.record_sha256}
    evidence_reconciliation=[pscustomobject]@{sha256=$fakeReconciliation.sha256;record_sha256=$fakeReconciliation.record.record_sha256};engine_run=[pscustomobject]@{path=[IO.Path]::GetFullPath($fakeEngineRunPath);sha256=(Get-FileHash $fakeEngineRunPath -Algorithm SHA256).Hash.ToUpperInvariant();record_sha256=$fakeEngineRun.record_sha256};runner=[pscustomobject]@{path=$fakeRunnerPath;sha256=(Get-FileHash $fakeRunnerPath -Algorithm SHA256).Hash.ToUpperInvariant()}
    targets=$fakeCampaignTargets;factorio_processes=4;release_qualification='passed';release_acceptance=@();technical_seal='not-performed';publication_authorized=$false;record_sha256=''
  }
  $fakeCampaign.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $fakeCampaign
  $fakeCampaignPath = Join-Path $root 'syntactically-valid-fake-campaign.json'
  Write-MIR4BootstrapRecord -Record $fakeCampaign -Path $fakeCampaignPath | Out-Null
  $fakeCampaignRejected = $false
  try { Get-MIR42RealEngineCandidateCampaign -RepoRoot $RepoRoot -Path $fakeCampaignPath -Candidate $readiness._state.candidate -Reconciliation $fakeReconciliation | Out-Null } catch { $fakeCampaignRejected = $_.Exception.Message -match 'mir42-seal-real-engine-executable-missing'; if (-not $fakeCampaignRejected) { throw $_ } }
  Assert-MIR42SealTest $fakeCampaignRejected 'synthetic-engine-campaign-rejected'
  $legacyPredecessorAuthority = [pscustomobject][ordered]@{
    schema=1;kind='MIR42DirectPredecessorInputsV1';status='verified-published-v410-checksum-and-local-custody-private'
    public_v410_checksums=[pscustomobject]@{tag='v4.1.0';tag_object=('A' * 40);tagged_commit=('B' * 40);path='.mir/releases/waves/mir4-r0/MIR42-v410-SHA256SUMS.txt';sha256=('C' * 64);verified_tag_fingerprint='SHA256:legacy'}
    targets=@();release_transition_authority=$false;publication_authorized=$false;record_sha256=''
  }
  $legacyPredecessorAuthority.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $legacyPredecessorAuthority
  $legacyPredecessorAuthorityPath = Join-Path $root 'legacy-predecessor-authority.json'
  Write-MIR4BootstrapRecord -Record $legacyPredecessorAuthority -Path $legacyPredecessorAuthorityPath | Out-Null
  $legacyPredecessorRejected = $false
  try {
    Get-MIR42DirectPredecessorAuthority -RepoRoot $RepoRoot -Reference ([pscustomobject]@{path=[IO.Path]::GetFullPath($legacyPredecessorAuthorityPath);sha256=(Get-FileHash $legacyPredecessorAuthorityPath -Algorithm SHA256).Hash.ToUpperInvariant();record_sha256=$legacyPredecessorAuthority.record_sha256}) | Out-Null
  } catch { $legacyPredecessorRejected = $_.Exception.Message -match 'mir42-seal-predecessor-checksums-shape'; if (-not $legacyPredecessorRejected) { throw $_ } }
  Assert-MIR42SealTest $legacyPredecessorRejected 'predecessor-authority-without-live-release-asset-rejected'
  $preparation = Join-Path $RepoRoot '.mir/releases/governance/mir4/signing-ceremony-preparation.json'
  $preparedOnly = Get-MIR42FourTargetTechnicalSealReadiness -RepoRoot $RepoRoot -CandidateManifestPath $manifestPath -SigningCeremonyPath $preparation
  Assert-MIR42SealTest (-not [bool]$preparedOnly.checks.signing -and -not [bool]$preparedOnly.technical_seal_authorized) 'preparation-is-not-approved-signer-and-recovery'
  $rejected = $false
  try { New-MIR42FourTargetTechnicalSeal -RepoRoot $RepoRoot -CandidateManifestPath $manifestPath -QualificationPath (Join-Path $root 'missing-qualification.json') -RealEngineCampaignPath (Join-Path $root 'missing-real-engine.json') -IndependentVerificationPath (Join-Path $root 'missing-independent.json') -SigningCeremonyPath (Join-Path $root 'missing-signing.json') -SourceFreezeAuthorityPath (Join-Path $root 'missing-freeze.json') -OutputPath (Join-Path $root 'seal.json') | Out-Null } catch { $rejected = $_.Exception.Message -match 'mir42-seal-not-authorized'; if (-not $rejected) { throw $_ } }
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
  $promotionRejected = $false
  try { Get-MIR42ProtectedMainPromotionPlan -RepoRoot $RepoRoot -TechnicalSealPath $sealPath -CandidateManifestPath $manifestPath -QualificationPath (Join-Path $root 'missing-qualification.json') -RealEngineCampaignPath (Join-Path $root 'missing-real-engine.json') -IndependentVerificationPath (Join-Path $root 'missing-independent.json') -SigningCeremonyPath (Join-Path $root 'missing-signing.json') -SourceFreezeAuthorityPath (Join-Path $root 'missing-freeze.json') -ReviewerAttestationPath (Join-Path $root 'missing-reviewer.json') -SshKeygenPath 'C:\Windows\System32\OpenSSH\ssh-keygen.exe' -OfflineRestoreDrillPath (Join-Path $root 'missing-restore-drill.json') | Out-Null } catch { $promotionRejected = $_.Exception.Message -match 'mir42-promotion-verified-seal-inputs' }
  Assert-MIR42SealTest $promotionRejected 'handwritten-seal-cannot-bypass-verified-inputs'
  $forgedRestore = [pscustomobject][ordered]@{
    schema=1;kind='MIR42FourTargetOfflineRestoreDrillV1';status='MIR-4.2-FOUR-TARGET-OFFLINE-RESTORE-DRILL-PASSED-PRIVATE-UNSEALED'
    source=$readiness._state.candidate.source;candidate_manifest=[pscustomobject]@{};technical_seal=[pscustomobject]@{}
    capsule=[pscustomobject]@{};restored_inventory=@();targets=@();clean_untracked_root=$true;publication_authorized=$false;record_sha256=''
  }
  $forgedRestore.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $forgedRestore
  $forgedRestorePath = Join-Path $root 'forged-selfhashed-offline-restore.json'
  Write-MIR4BootstrapRecord -Record $forgedRestore -Path $forgedRestorePath | Out-Null
  $forgedRestoreRejected = $false
  try {
    Get-MIR42GovernedOfflineRestoreDrill -RepoRoot $RepoRoot -Path $forgedRestorePath -Candidate $readiness._state.candidate -Seal (Read-MIR42SealRecord -Path $sealPath -Code 'test-seal') -Signing ([pscustomobject]@{sha256=('A' * 64);record=[pscustomobject]@{record_sha256=('B' * 64)}}) -SshKeygenPath 'C:\Windows\System32\OpenSSH\ssh-keygen.exe' | Out-Null
  } catch { $forgedRestoreRejected = $_.Exception.Message -match 'mir42-promotion-governed-restore-shape'; if (-not $forgedRestoreRejected) { throw $_ } }
  Assert-MIR42SealTest $forgedRestoreRejected 'selfhashed-same-session-offline-restore-rejected'
  $promotionText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42ProtectedMainPromotion.ps1')
  Assert-MIR42SealTest ($promotionText -match 'refs/heads/main' -and $promotionText -match 'refs/heads/dev' -and $promotionText -match 'candidateRef' -and $promotionText -match 'MIR42FourTargetGovernedOfflineRestoreDrillV1' -and $promotionText -notmatch 'MIR42FourTargetOfflineRestoreDrillV1|push origin|--force') 'protected-pr-remote-readback-no-push'

  $sourceDrift = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $sourceDrift.source.tree = '0' * 40
  $sourceDrift.record_sha256 = ''
  $sourceDrift.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $sourceDrift
  $sourceDriftPath = Join-Path $root 'candidate-source-drift.json'
  Write-MIR4BootstrapRecord -Record $sourceDrift -Path $sourceDriftPath | Out-Null
  $sourceRejected = $false
  try { Get-MIR42ExactFourTargetCandidate -RepoRoot $RepoRoot -CandidateManifestPath $sourceDriftPath | Out-Null } catch { $sourceRejected = $_.Exception.Message -match 'mir42-seal-candidate-source-tree-drift' }
  Assert-MIR42SealTest $sourceRejected 'candidate-tree-drift-rejected'

  $escape = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $escape.targets[0].asset.path = '../outside.zip'
  $escape.record_sha256 = ''
  $escape.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $escape
  $escapePath = Join-Path $root 'candidate-escape.json'
  Write-MIR4BootstrapRecord -Record $escape -Path $escapePath | Out-Null
  $escapeRejected = $false
  try { Get-MIR42ExactFourTargetCandidate -RepoRoot $RepoRoot -CandidateManifestPath $escapePath | Out-Null } catch { $escapeRejected = $_.Exception.Message -match 'mir42-seal-candidate-asset-path' }
  Assert-MIR42SealTest $escapeRejected 'candidate-asset-traversal-rejected'

  $plainPath = Join-Path $root 'invalid/more-infinite-research_4.2.21000.zip'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $plainPath) | Out-Null
  [IO.File]::WriteAllText($plainPath, 'not-a-zip', [Text.UTF8Encoding]::new($false))
  $plainAsset = [pscustomobject]@{path='invalid/more-infinite-research_4.2.21000.zip';bytes=[int64](Get-Item $plainPath).Length;sha256=(Get-FileHash $plainPath -Algorithm SHA256).Hash.ToUpperInvariant()}
  $plainRow = Get-Content -Raw -LiteralPath (Join-Path $root 'target-rows/f210.json') | ConvertFrom-Json -Depth 100 -DateKind String
  $plainRow.asset = $plainAsset; $plainRow.content_sha256 = ('E' * 64); $plainRow.entry_count = 1; $plainRow.build_a_sha256 = $plainAsset.sha256; $plainRow.build_b_sha256 = $plainAsset.sha256; $plainRow.record_sha256 = ''
  $plainRow.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $plainRow
  $plainRowPath = Join-Path $root 'target-rows/f210-invalid.json'
  Write-MIR4BootstrapRecord -Record $plainRow -Path $plainRowPath | Out-Null
  $plain = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $plain.targets[0].asset = $plainAsset; $plain.targets[0].content_sha256 = ('E' * 64); $plain.targets[0].entry_count = 1; $plain.targets[0].target_row_path = 'target-rows/f210-invalid.json'; $plain.record_sha256 = ''
  $plain.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $plain
  $plainManifestPath = Join-Path $root 'candidate-plain-zip.json'
  Write-MIR4BootstrapRecord -Record $plain -Path $plainManifestPath | Out-Null
  $plainRejected = $false
  try { Get-MIR42ExactFourTargetCandidate -RepoRoot $RepoRoot -CandidateManifestPath $plainManifestPath | Out-Null } catch { $plainRejected = $_.Exception.Message -match 'mir42-seal-candidate-archive-invalid' }
  Assert-MIR42SealTest $plainRejected 'candidate-plain-text-zip-rejected'

  # A syntactically complete chain with real alternate signatures is still not
  # authority when all of its roots live in the mutable candidate workspace.
  $sshKeygen = 'C:\Windows\System32\OpenSSH\ssh-keygen.exe'
  $testAclSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $testAclContract = New-MIR42T16AclContract -ApprovedOwnerSid $testAclSid -ApprovedMutationSids @($testAclSid)
  $forgedTrustRoot = Join-Path $root 'coherent-alternate-t16'
  New-Item -ItemType Directory -Force -Path $forgedTrustRoot | Out-Null
  $forgedOperatorPrivate = Join-Path $forgedTrustRoot 'alternate-operator'
  & $sshKeygen -q -t ed25519 -N '' -f $forgedOperatorPrivate | Out-Null
  Assert-MIR42SealTest ($LASTEXITCODE -eq 0) 'coherent-alternate-key-created'
  $forgedOperatorPublicPath = $forgedOperatorPrivate + '.pub'
  $forgedOperatorPublic = (Get-Content -Raw -LiteralPath $forgedOperatorPublicPath).Trim()
  $forgedOperatorFingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $sshKeygen -PublicKeyPath $forgedOperatorPublicPath
  $forgedOperator = [pscustomobject][ordered]@{
    schema=1;kind='MIR42ExternalOperatorTrustSourceV1';status='active-external-protected-operator-trust-source'
    operator=[pscustomobject]@{identity='alternate-operator';algorithm='ssh-ed25519';public_key=$forgedOperatorPublic;fingerprint=$forgedOperatorFingerprint}
    namespaces=@('mir4-t16-trust-root');record_sha256=''
  }
  $forgedOperator.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $forgedOperator
  $forgedOperatorPath = Join-Path $forgedTrustRoot 'operator-trust.json'
  Write-MIR4BootstrapRecord -Record $forgedOperator -Path $forgedOperatorPath | Out-Null
  $forgedRootPath = Join-Path $forgedTrustRoot 't16-ledger-trust-root.json'
  $forgedRootSignaturePath = $forgedRootPath + '.sig'
  $forgedRoot = [pscustomobject][ordered]@{
    schema=1;kind='MIR42ExternalT16LedgerTrustRootV1';status='MIR-4.2-T16-PROTECTED-SIGNING-RECOVERY-ACCEPTED';release_line='4.2';turn='T16';scope='four-target-release-cut'
    signing_ceremony=[pscustomobject]@{path=(Join-Path $forgedTrustRoot 'alternate-signing-ceremony.json');sha256=('A' * 64);record_sha256=('B' * 64)}
    authorized_signer=[pscustomobject]@{principal='alternate-operator';algorithm='ssh-ed25519';public_key=$forgedOperatorPublic;fingerprint=$forgedOperatorFingerprint;namespaces=@('mir4-source','mir4-target','mir4-ledger')}
    independent_reviewer=[pscustomobject]@{identity='alternate-reviewer';public_key=$forgedOperatorPublic;fingerprint=$forgedOperatorFingerprint}
    recovery=[pscustomobject]@{synthetic='not-accepted'}
    operator_trust=[pscustomobject]@{path=$forgedOperatorPath;sha256=(Get-FileHash -LiteralPath $forgedOperatorPath -Algorithm SHA256).Hash.ToUpperInvariant();record_sha256=$forgedOperator.record_sha256}
    verifier=$verifierAuthority
    ledger=[pscustomobject]@{repository_path=$RepoRoot;ref='refs/heads/release-ledger/mir4';commit=('0' * 40);event_path='t16-ledger-trust-root.json';event_sha256=('C' * 64)}
    trust_signature=[pscustomobject]@{identity='alternate-operator';namespace='mir4-t16-trust-root';signature_path=$forgedRootSignaturePath;signature_sha256='';payload_sha256=''};record_sha256=''
  }
  $forgedRootPayload = ConvertTo-MIR4BootstrapCanonicalJson -Value (Get-MIR42T16TrustRootSignaturePayload -Record $forgedRoot)
  $forgedRootPayloadPath = Join-Path $forgedTrustRoot 't16-root-payload.json'
  [IO.File]::WriteAllText($forgedRootPayloadPath, $forgedRootPayload, [Text.UTF8Encoding]::new($false))
  & $sshKeygen -Y sign -f $forgedOperatorPrivate -n 'mir4-t16-trust-root' $forgedRootPayloadPath | Out-Null
  $generatedSignaturePath = $forgedRootPayloadPath + '.sig'
  Move-Item -LiteralPath $generatedSignaturePath -Destination $forgedRootSignaturePath
  Assert-MIR42SealTest (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $sshKeygen -PublicKeyPath $forgedOperatorPublicPath -Identity 'alternate-operator' -Namespace 'mir4-t16-trust-root' -PayloadPath $forgedRootPayloadPath -SignaturePath $forgedRootSignaturePath -ScratchRoot (Join-Path $forgedTrustRoot 'verify')) 'coherent-alternate-root-signature-valid'
  $forgedRoot.trust_signature.signature_sha256 = (Get-FileHash -LiteralPath $forgedRootSignaturePath -Algorithm SHA256).Hash.ToUpperInvariant()
  $forgedRoot.trust_signature.payload_sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($forgedRootPayload)))
  $forgedRoot.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $forgedRoot
  Write-MIR4BootstrapRecord -Record $forgedRoot -Path $forgedRootPath | Out-Null
  $forgedTrustRejected = $false
  try { Get-MIR42ExternalT16LedgerTrustRoot -RepoRoot $RepoRoot -T16TrustRootPath $forgedRootPath -OperatorTrustSourcePath $forgedOperatorPath -ProtectedRootPath $forgedTrustRoot -ImmutableAnchorPath ([IO.Path]::GetPathRoot($forgedTrustRoot)) -AclContract $testAclContract -SshKeygenPath $sshKeygen | Out-Null } catch { $forgedTrustRejected = $_.Exception.Message -match 'mir42-seal-external-t16-(immutable-anchor-not-protected|protected-root-repository)' }
  Assert-MIR42SealTest $forgedTrustRejected 'coherent-alternate-t16-chain-in-candidate-rejected'

  # Moving the same alternate key chain beside the checkout does not make it
  # trusted: the current identity can still mutate the external source.
  $externalForgedTrustRoot = Join-Path ((Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).Path) ('mir42-writable-external-t16-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $externalForgedTrustRoot | Out-Null
  $externalOperator = $forgedOperator | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $externalOperator.record_sha256 = ''
  $externalOperator.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $externalOperator
  $externalOperatorPath = Join-Path $externalForgedTrustRoot 'operator-trust.json'
  Write-MIR4BootstrapRecord -Record $externalOperator -Path $externalOperatorPath | Out-Null
  $externalRoot = $forgedRoot | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $externalRoot.signing_ceremony.path = Join-Path $externalForgedTrustRoot 'alternate-signing-ceremony.json'
  $externalRoot.operator_trust.path = $externalOperatorPath
  $externalRoot.operator_trust.sha256 = (Get-FileHash -LiteralPath $externalOperatorPath -Algorithm SHA256).Hash.ToUpperInvariant()
  $externalRoot.operator_trust.record_sha256 = $externalOperator.record_sha256
  $externalRoot.ledger.repository_path = $externalForgedTrustRoot
  $externalRoot.trust_signature.signature_path = Join-Path $externalForgedTrustRoot 't16-ledger-trust-root.json.sig'
  $externalRoot.trust_signature.signature_sha256 = ''
  $externalRoot.trust_signature.payload_sha256 = ''
  $externalRoot.record_sha256 = ''
  $externalRootPayload = ConvertTo-MIR4BootstrapCanonicalJson -Value (Get-MIR42T16TrustRootSignaturePayload -Record $externalRoot)
  $externalRootPayloadPath = Join-Path $externalForgedTrustRoot 't16-root-payload.json'
  [IO.File]::WriteAllText($externalRootPayloadPath, $externalRootPayload, [Text.UTF8Encoding]::new($false))
  & $sshKeygen -Y sign -f $forgedOperatorPrivate -n 'mir4-t16-trust-root' $externalRootPayloadPath | Out-Null
  Move-Item -LiteralPath ($externalRootPayloadPath + '.sig') -Destination $externalRoot.trust_signature.signature_path
  Assert-MIR42SealTest (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $sshKeygen -PublicKeyPath $forgedOperatorPublicPath -Identity 'alternate-operator' -Namespace 'mir4-t16-trust-root' -PayloadPath $externalRootPayloadPath -SignaturePath $externalRoot.trust_signature.signature_path -ScratchRoot (Join-Path $externalForgedTrustRoot 'verify')) 'coherent-writable-external-root-signature-valid'
  $externalRoot.trust_signature.signature_sha256 = (Get-FileHash -LiteralPath $externalRoot.trust_signature.signature_path -Algorithm SHA256).Hash.ToUpperInvariant()
  $externalRoot.trust_signature.payload_sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($externalRootPayload)))
  $externalRoot.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $externalRoot
  $externalRootPath = Join-Path $externalForgedTrustRoot 't16-ledger-trust-root.json'
  Write-MIR4BootstrapRecord -Record $externalRoot -Path $externalRootPath | Out-Null
  $writableExternalTrustRejected = $false
  try { Get-MIR42ExternalT16LedgerTrustRoot -RepoRoot $RepoRoot -T16TrustRootPath $externalRootPath -OperatorTrustSourcePath $externalOperatorPath -ProtectedRootPath $externalForgedTrustRoot -ImmutableAnchorPath ([IO.Path]::GetPathRoot($externalForgedTrustRoot)) -AclContract $testAclContract -SshKeygenPath $sshKeygen | Out-Null } catch { $writableExternalTrustRejected = $_.Exception.Message -match 'mir42-seal-external-t16-(immutable-anchor-not-protected|protected-root-not-protected)' }
  Assert-MIR42SealTest $writableExternalTrustRejected 'coherent-writable-external-t16-chain-rejected'

  $aclProbePath = Join-Path $root 'unapproved-mutation-ace.txt'
  [IO.File]::WriteAllText($aclProbePath, 'acl probe', [Text.UTF8Encoding]::new($false))
  $probeAcl = [Security.AccessControl.FileSecurity]::new()
  $probeAcl.SetOwner([Security.Principal.SecurityIdentifier]$testAclSid)
  $probeAcl.SetAccessRuleProtection($true,$false)
  $probeAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]$testAclSid,[Security.AccessControl.FileSystemRights]::FullControl,[Security.AccessControl.AccessControlType]::Allow))
  $unapprovedSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-21-777777777-666666666-555555555-444444444')
  $probeAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($unapprovedSid,[Security.AccessControl.FileSystemRights]::Modify,[Security.AccessControl.AccessControlType]::Allow))
  Set-Acl -LiteralPath $aclProbePath -AclObject $probeAcl
  $unapprovedAceRejected = $false
  try { Assert-MIR42SealT16AclContract -Path $aclProbePath -AclContract $testAclContract -Code 'mir42-seal-test-unapproved-ace' } catch { $unapprovedAceRejected = $_.Exception.Message -match 'mir42-seal-test-unapproved-ace-acl-allow-sid' }
  Assert-MIR42SealTest $unapprovedAceRejected 'unapproved-mutable-sid-ace-rejected'

  $ancestorTrustRoot = Join-Path $root 'ancestor-trust-root'
  $ancestorTrustParent = Join-Path $ancestorTrustRoot 'trust-parent'
  $ancestorTrustFile = Join-Path $ancestorTrustParent 'trust.json'
  New-Item -ItemType Directory -Force -Path $ancestorTrustParent | Out-Null
  [IO.File]::WriteAllText($ancestorTrustFile, 'trust', [Text.UTF8Encoding]::new($false))
  foreach ($path in @($ancestorTrustRoot,$ancestorTrustParent,$ancestorTrustFile)) { Set-MIR42SealTestExactAcl -Path $path -OwnerSid $testAclSid }
  $unapprovedSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-21-777777777-666666666-555555555-444444444')
  Assert-MIR42SealT16AclProtectedAncestors -ArtifactPath $ancestorTrustFile -ProtectedRootPath $ancestorTrustRoot -AclContract $testAclContract -Code 'mir42-seal-test-trust-parent-positive'
  $trustParentAssessment = Get-MIR42SealAclAssessment -Path $ancestorTrustParent -Code 'mir42-seal-test-trust-parent'
  $readOnlyAncestorAssessment = $trustParentAssessment | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 -DateKind String
  $readOnlyAncestorAssessment.rows = @($readOnlyAncestorAssessment.rows) + @([pscustomobject]@{sid='S-1-1-0';type='Allow';rights=[Security.AccessControl.FileSystemRights]::ReadAndExecute;inherited=$false})
  $readOnlyAncestorAccepted = $true
  try { Assert-MIR42SealT16AclAncestorAssessment -Assessment $readOnlyAncestorAssessment -AclContract $testAclContract -Code 'mir42-seal-test-read-only-parent' } catch { $readOnlyAncestorAccepted = $false }
  Assert-MIR42SealTest $readOnlyAncestorAccepted 'read-only-parent-ace-allowed'
  $trustParentAssessment.rows = @($trustParentAssessment.rows) + @([pscustomobject]@{sid=$unapprovedSid.Value;type='Allow';rights=[Security.AccessControl.FileSystemRights]::Modify;inherited=$false})
  $unapprovedTrustParentRejected = $false
  try { Assert-MIR42SealT16AclAncestorAssessment -Assessment $trustParentAssessment -AclContract $testAclContract -Code 'mir42-seal-test-trust-parent' } catch { $unapprovedTrustParentRejected = $_.Exception.Message -match 'mir42-seal-test-trust-parent-acl-ancestor-allow-sid' }
  Assert-MIR42SealTest $unapprovedTrustParentRejected 'unapproved-trust-parent-mutation-ace-rejected'

  $ancestorLedgerRoot = Join-Path $root 'ancestor-ledger-root'
  $ancestorLedgerParent = Join-Path $ancestorLedgerRoot 'ledger-parent'
  $ancestorLedgerDirectory = Join-Path $ancestorLedgerParent 'ledger'
  New-Item -ItemType Directory -Force -Path $ancestorLedgerDirectory | Out-Null
  foreach ($path in @($ancestorLedgerRoot,$ancestorLedgerParent,$ancestorLedgerDirectory)) { Set-MIR42SealTestExactAcl -Path $path -OwnerSid $testAclSid }
  Assert-MIR42SealT16AclProtectedAncestors -ArtifactPath $ancestorLedgerDirectory -ProtectedRootPath $ancestorLedgerRoot -AclContract $testAclContract -Code 'mir42-seal-test-ledger-parent-positive'
  $ledgerParentAssessment = Get-MIR42SealAclAssessment -Path $ancestorLedgerParent -Code 'mir42-seal-test-ledger-parent'
  $ledgerParentAssessment.rows = @($ledgerParentAssessment.rows) + @([pscustomobject]@{sid=$unapprovedSid.Value;type='Allow';rights=[Security.AccessControl.FileSystemRights]::Modify;inherited=$false})
  $unapprovedLedgerParentRejected = $false
  try { Assert-MIR42SealT16AclAncestorAssessment -Assessment $ledgerParentAssessment -AclContract $testAclContract -Code 'mir42-seal-test-ledger-parent' } catch { $unapprovedLedgerParentRejected = $_.Exception.Message -match 'mir42-seal-test-ledger-parent-acl-ancestor-allow-sid' }
  Assert-MIR42SealTest $unapprovedLedgerParentRejected 'unapproved-ledger-parent-mutation-ace-rejected'

  $immutableAnchor = Join-Path $root 'immutable-anchor'
  $protectedRootParent = Join-Path $immutableAnchor 'protected-root-parent'
  $protectedRoot = Join-Path $protectedRootParent 'protected-root'
  New-Item -ItemType Directory -Force -Path $protectedRoot | Out-Null
  foreach ($path in @($immutableAnchor,$protectedRootParent,$protectedRoot)) { Set-MIR42SealTestExactAcl -Path $path -OwnerSid $testAclSid }
  Assert-MIR42SealT16AclRootToImmutableAnchor -ProtectedRootPath $protectedRoot -ImmutableAnchorPath $immutableAnchor -AclContract $testAclContract -Code 'mir42-seal-test-protected-root-anchor-positive'
  $unapprovedParentGrant = '*S-1-5-32-545:(M)'
  & "$env:SystemRoot\System32\icacls.exe" $protectedRootParent '/grant' $unapprovedParentGrant | Out-Null
  Assert-MIR42SealTest ($LASTEXITCODE -eq 0) 'unapproved-protected-root-parent-ace-created'
  $unapprovedProtectedRootParentRejected = $false
  try { Assert-MIR42SealT16AclRootToImmutableAnchor -ProtectedRootPath $protectedRoot -ImmutableAnchorPath $immutableAnchor -AclContract $testAclContract -Code 'mir42-seal-test-protected-root-parent' } catch { $unapprovedProtectedRootParentRejected = $_.Exception.Message -match 'mir42-seal-test-protected-root-parent-acl-ancestor-allow-sid' }
  Assert-MIR42SealTest $unapprovedProtectedRootParentRejected 'unapproved-parent-above-protected-root-rejected'
  $immutableAnchorAssessment = Get-MIR42SealAclAssessment -Path $immutableAnchor -Code 'mir42-seal-test-immutable-anchor'
  $immutableAnchorAssessment.owner_sid = $unapprovedSid.Value
  $unapprovedAnchorOwnerRejected = $false
  try { Assert-MIR42SealT16AclImmutableAnchorAssessment -Assessment $immutableAnchorAssessment -AclContract $testAclContract -Code 'mir42-seal-test-immutable-anchor' } catch { $unapprovedAnchorOwnerRejected = $_.Exception.Message -match 'mir42-seal-test-immutable-anchor-acl-anchor-owner' }
  Assert-MIR42SealTest $unapprovedAnchorOwnerRejected 'unapproved-immutable-anchor-owner-rejected'

  $forgedFreeze = [pscustomobject][ordered]@{
    schema=1;kind='MIR42SourceFreezeAuthorizationV1';status='MIR-4.2-SOURCE-FROZEN-AND-CANDIDATE-ALLOCATED'
    source=$readiness._state.candidate.source;candidate_manifest=[pscustomobject]@{sha256=$readiness._state.candidate.identity.sha256;record_sha256=$readiness._state.candidate.identity.record.record_sha256}
    frozen_dev=[pscustomobject]@{ref='refs/heads/dev';commit=$readiness._state.candidate.source.commit;tree=$readiness._state.candidate.source.tree}
    promotion_base=[pscustomobject]@{remote='origin';ref='refs/heads/main';commit=('E' * 40)}
    programme=[pscustomobject]@{path='.mir/releases/governance/mir4/MIR42-Release-Cut-ProgrammeV1.json';sha256=('F' * 64);source_freeze_state='True';candidate_allocation_state='True'}
    signing_ceremony=[pscustomobject]@{sha256=('C' * 64);record_sha256=('D' * 64)}
    transition_gate=[pscustomobject]@{source_freeze=$true;candidate_allocation=$true;production_signing=$true;technical_seal=$false}
    independent_reviewer=[pscustomobject]@{identity='independent-reviewer';public_key='ssh-ed25519 AAAA reviewer';fingerprint='SHA256:reviewer'}
    ledger_signature=[pscustomobject]@{verified=$true;namespace='mir4-ledger'};record_sha256=''
  }
  $forgedFreeze.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $forgedFreeze
  $forgedFreezePath = Join-Path $root 'forged-freeze.json'
  Write-MIR4BootstrapRecord -Record $forgedFreeze -Path $forgedFreezePath | Out-Null
  $forgedRejected = $false
  $fakeSigning = [pscustomobject]@{sha256=('C' * 64);record=[pscustomobject]@{record_sha256=('D' * 64)};ledger_signer=[pscustomobject]@{principal='mir4-release-signing';public_key='ssh-ed25519 AAAA test';fingerprint='SHA256:test'}}
  try { Get-MIR42SourceFreezeAuthority -RepoRoot $RepoRoot -Path $forgedFreezePath -Candidate $readiness._state.candidate -Signing $fakeSigning -SshKeygenPath 'C:\Windows\System32\OpenSSH\ssh-keygen.exe' | Out-Null } catch { $forgedRejected = $_.Exception.Message -match 'mir42-seal-freeze-ledger-signature-shape'; if (-not $forgedRejected) { throw $_ } }
  Assert-MIR42SealTest $forgedRejected 'forged-freeze-verified-flag-rejected'

  $fakeIndependent = [pscustomobject]@{sha256=('F' * 64);record=[pscustomobject]@{record_sha256=('A' * 64)}}
  $fakeCampaign = [pscustomobject]@{sha256=('B' * 64);record=[pscustomobject]@{record_sha256=('C' * 64);release_acceptance=@()}}
  $fakeFreeze = [pscustomobject]@{sha256=('D' * 64);record=[pscustomobject]@{record_sha256=('E' * 64);independent_reviewer=$forgedFreeze.independent_reviewer}}
  $forgedReview = [pscustomobject][ordered]@{
    schema=1;kind='MIR42IndependentReviewerAttestationV1';status='MIR-4.2-INDEPENDENT-REVIEW-ACCEPTED'
    independent_verification=[pscustomobject]@{sha256=$fakeIndependent.sha256;record_sha256=$fakeIndependent.record.record_sha256}
    real_engine_campaign=[pscustomobject]@{sha256=$fakeCampaign.sha256;record_sha256=$fakeCampaign.record.record_sha256}
    source_freeze_authority=[pscustomobject]@{sha256=$fakeFreeze.sha256;record_sha256=$fakeFreeze.record.record_sha256}
    acceptance_coverage=@();reviewer=$forgedFreeze.independent_reviewer;review_signature=[pscustomobject]@{verified=$true;namespace='mir4-independent-review'};record_sha256=''
  }
  $forgedReview.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $forgedReview
  $forgedReviewPath = Join-Path $root 'forged-review.json'
  Write-MIR4BootstrapRecord -Record $forgedReview -Path $forgedReviewPath | Out-Null
  $forgedReviewRejected = $false
  try { Get-MIR42IndependentReviewerAttestation -RepoRoot $RepoRoot -Path $forgedReviewPath -Independent $fakeIndependent -Campaign $fakeCampaign -Freeze $fakeFreeze -SshKeygenPath 'C:\Windows\System32\OpenSSH\ssh-keygen.exe' | Out-Null } catch { $forgedReviewRejected = $_.Exception.Message -match 'mir42-seal-reviewer-signature-shape'; if (-not $forgedReviewRejected) { throw $_ } }
  Assert-MIR42SealTest $forgedReviewRejected 'forged-reviewer-verified-flag-rejected'

  [IO.File]::AppendAllText((Join-Path $root ([string]$targets[0].asset.path)),'drift',[Text.UTF8Encoding]::new($false))
  $assetRejected = $false
  try { Get-MIR42ExactFourTargetCandidate -RepoRoot $RepoRoot -CandidateManifestPath $manifestPath | Out-Null } catch { $assetRejected = $_.Exception.Message -match 'mir42-seal-candidate-asset-drift' }
  Assert-MIR42SealTest $assetRejected 'candidate-asset-drift-rejected'
  Write-Output 'MIR 4.2 seal passed exact-archive, path, source, real-engine, external T16 trust-root, forged-freeze, missing-evidence, and no-bypass checks; no remote mutation occurred.'
} finally {
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
  if (-not [string]::IsNullOrWhiteSpace($externalForgedTrustRoot) -and (Test-Path -LiteralPath $externalForgedTrustRoot)) {
    $external = (Resolve-Path -LiteralPath $externalForgedTrustRoot).Path
    $temp = (Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).Path.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
    if (-not $external.StartsWith($temp + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw "[mir42-seal-test-external-cleanup-path] $external" }
    Remove-Item -LiteralPath $external -Recurse -Force
  }
}
