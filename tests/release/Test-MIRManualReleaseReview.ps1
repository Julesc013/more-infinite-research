# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [string]$Path = "",
  [string]$Candidate = "",
  [string]$FactorioBin = "",
  [string]$ExpectedSourceCommit = "",
  [string]$ExpectedFactorioVersion = "",
  [switch]$SelfTest
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"
$ErrorActionPreference = "Stop"
. (Join-Path $MirLegacyScriptRoot "validation\ReleaseAttestations.ps1")

function Assert-MIRManualReleaseReviewTest {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[mir-manual-release-review-test-$Code]" }
}

function Assert-MIRManualReleaseReviewReject {
  param([Parameter(Mandatory)][scriptblock]$Action,[Parameter(Mandatory)][string]$Pattern,[Parameter(Mandatory)][string]$Code)
  $rejected = $false
  try { & $Action | Out-Null } catch { $rejected = $_.Exception.Message -match $Pattern }
  Assert-MIRManualReleaseReviewTest -Condition $rejected -Code $Code
}

if ($SelfTest) {
  $root = Join-Path $RepoRoot ('build/test-results/mir-manual-written-waiver-' + [guid]::NewGuid().ToString('N'))
  $factorioVersionReader = (Get-Item Function:Get-MIRReleaseFactorioVersion).ScriptBlock
  try {
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $candidateSource = Join-Path $root 'candidate-source'
    $candidateContent = Join-Path $candidateSource 'fixture'
    New-Item -ItemType Directory -Force -Path $candidateContent | Out-Null
    [IO.File]::WriteAllText((Join-Path $candidateContent 'info.json'), '{"name":"mir-fixture","version":"4.2.21000","factorio_version":"2.1"}', [Text.UTF8Encoding]::new($false))
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $candidate = Join-Path $root 'candidate.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($candidateSource, $candidate)
    $factorio = Join-Path $root 'factorio.exe'
    [IO.File]::WriteAllText($factorio, 'fixture-factorio', [Text.UTF8Encoding]::new($false))
    Set-Item Function:Get-MIRReleaseFactorioVersion -Value { param($Path) return '2.1.0' }
    . (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42ReleaseAssets.ps1')
    $authorization = [pscustomobject][ordered]@{
      schema=1;kind='MIR42MaintainerWrittenReleaseAuthorizationHandoffV1';status='written-maintainer-authorization-recorded-awaiting-exact-candidate-and-technical-proof'
      recorded_from_user_turn_date='2026-10-02';timezone='Australia/Sydney'
      release=[ordered]@{source_version='4.2.0';tag='v4.2.0';selected_targets=@('f210','f200','f110','f100','f017','f016','f015','f014','f013')}
      written_authorizations=[ordered]@{complete_mir_4_2='authorized-subject-to-required-technical-checks';protected_main_promotion='authorized-after-accepted-technical-seal-and-governed-restore';required_distribution_tags='authorized-after-protected-main-readback-and-candidate-bound-go';github_publication='authorized-after-final-byte-acceptance-and-tag-verification';nine_target_github_zip_assets='authorized-after-final-byte-acceptance';mod_portal_upload='not-claimed-by-this-github-release-authorization'}
      maintainer_decisions=[ordered]@{current_balance_direction='accepted';current_visual_direction='accepted';disclosed_limitations='accepted';additional_playtest_prompt='waived-for-this-release-decision';experimental_f210='qualified-experimental-consent-recorded';f210_f200_playtest_receipt='not-claimed-and-not-materialized';technical_acceptance='not-established';candidate_binding='deferred-until-one-exact-accepted-candidate';final_byte_hashes='not-yet-available'}
      nonnegotiable_constraints=@('fixture constraint')
      current_controller_state=[ordered]@{programme_path='.mir/releases/governance/mir4/MIR42-Nine-Target-Release-Cut-ProgrammeV1.json';programme_status='active-current-4.2-release-cut-pre-freeze-no-transition-authority';source_freeze=$false;candidate_allocation=$false;production_signing=$false;technical_seal=$false;promotion=$false;tagging=$false;publication=$false}
      required_external_inputs_before_technical_seal=@([ordered]@{name='fixture';required_path='external fixture';state='absent'})
      known_operator_inputs=[ordered]@{ssh_keygen_path='C:/Windows/System32/OpenSSH/ssh-keygen.exe';existing_signer_public_fingerprint='SHA256:McpdYUux7BcYmBkf75fGuHSn/lYkTHB6ngMOdUJ5ggQ';signer_continuity_policy='existing-MIR-dedicated-signer-continuity';signer_probe_disposition='automatic-review-rejected-no-retry-or-workaround';rejection_record='AUTOMATIC-REVIEW-REJECTION.txt'}
      final_byte_binding=[ordered]@{candidate_manifest_path='deferred';technical_seal_path='deferred';frozen_inventory_path='deferred';required_binding='fixture binds after exact proof'}
      secret_values_present=$false;warning='fixture only';record_sha256=''
    }
    $authorizationPath = Join-Path $root 'authorization.json'
    Write-MIR4BootstrapRecord -Record $authorization -Path $authorizationPath | Out-Null
    $waiverPath = Join-Path $root 'waiver.json'
    $written = New-MIRManualReleaseWrittenWaiverAttestation -RepoRoot $RepoRoot -Candidate $candidate -FactorioBin $factorio -ExpectedSourceCommit ('a' * 40) -ExpectedFactorioVersion '2.1' -MaintainerAuthorizationPath $authorizationPath -Path $waiverPath
    $validWaiverBytes = [IO.File]::ReadAllBytes($waiverPath)
    $validated = Test-MIRManualReleaseAttestation -RepoRoot $RepoRoot -Path $waiverPath -Candidate $candidate -FactorioBin $factorio -ExpectedSourceCommit ('a' * 40) -ExpectedFactorioVersion '2.1'
    Assert-MIRManualReleaseReviewTest -Condition ([string]$written.status -eq 'waived' -and [string]$validated.status -eq 'waived' -and [string]$validated.disposition -eq 'written-maintainer-playtest-waiver' -and -not [bool]$validated.manual_review_performed -and -not [bool]$validated.gameplay_receipt_claimed) -Code 'valid-written-waiver'
    [IO.File]::WriteAllText((Join-Path $candidateContent 'info.json'), '{"name":"mir-fixture","version":"4.3.21000","factorio_version":"2.1"}', [Text.UTF8Encoding]::new($false))
    $otherReleaseCandidate = Join-Path $root 'candidate-other-release.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($candidateSource, $otherReleaseCandidate)
    Assert-MIRManualReleaseReviewReject -Action { New-MIRManualReleaseWrittenWaiverAttestation -RepoRoot $RepoRoot -Candidate $otherReleaseCandidate -FactorioBin $factorio -ExpectedSourceCommit ('a' * 40) -ExpectedFactorioVersion '2.1' -MaintainerAuthorizationPath $authorizationPath -Path (Join-Path $root 'other-release-waiver.json') } -Pattern '\[mir-manual-review-waiver-candidate-version\]' -Code 'other-release-candidate-rejected'
    [IO.File]::WriteAllText((Join-Path $candidateContent 'info.json'), '{"name":"mir-fixture","version":"4.2.21000","factorio_version":"2.1"}', [Text.UTF8Encoding]::new($false))
    $waiver = Get-Content -Raw -LiteralPath $waiverPath | ConvertFrom-Json
    $waiver.gameplay_receipt_claimed = $true
    $waiverMap = ConvertTo-MIRReleaseOrderedMap -Object $waiver
    $waiverMap.Remove('attestation_sha256')
    $waiverMap.attestation_sha256 = Get-MIRReleaseTextSha256 -Text ($waiverMap | ConvertTo-Json -Depth 40 -Compress)
    [IO.File]::WriteAllText($waiverPath, ($waiverMap | ConvertTo-Json -Depth 40 -Compress) + "`n", [Text.UTF8Encoding]::new($false))
    Assert-MIRManualReleaseReviewReject -Action { Test-MIRManualReleaseAttestation -RepoRoot $RepoRoot -Path $waiverPath -Candidate $candidate -FactorioBin $factorio -ExpectedSourceCommit ('a' * 40) -ExpectedFactorioVersion '2.1' } -Pattern '\[mir-manual-release-attestation-schema\]|\[mir-manual-review-waiver-observation\]' -Code 'claimed-gameplay-rejected'
    [IO.File]::WriteAllBytes($waiverPath, $validWaiverBytes)
    $waiver = Get-Content -Raw -LiteralPath $waiverPath | ConvertFrom-Json
    $waiver | Add-Member -NotePropertyName reviewer -NotePropertyValue 'self-signed-proof'
    $waiverMap = ConvertTo-MIRReleaseOrderedMap -Object $waiver
    $waiverMap.Remove('attestation_sha256')
    $waiverMap.attestation_sha256 = Get-MIRReleaseTextSha256 -Text ($waiverMap | ConvertTo-Json -Depth 40 -Compress)
    [IO.File]::WriteAllText($waiverPath, ($waiverMap | ConvertTo-Json -Depth 40 -Compress) + "`n", [Text.UTF8Encoding]::new($false))
    Assert-MIRManualReleaseReviewReject -Action { Test-MIRManualReleaseAttestation -RepoRoot $RepoRoot -Path $waiverPath -Candidate $candidate -FactorioBin $factorio -ExpectedSourceCommit ('a' * 40) -ExpectedFactorioVersion '2.1' } -Pattern '\[mir-manual-release-attestation-schema\]|\[mir-manual-review-waiver-observation\]' -Code 'self-signed-proof-rejected'
    $authorization.maintainer_decisions.technical_acceptance = 'accepted'
    $authorization.record_sha256 = ''
    $invalidAuthorizationPath = Join-Path $root 'authorization-technical-claim.json'
    Write-MIR4BootstrapRecord -Record $authorization -Path $invalidAuthorizationPath | Out-Null
    $waiver = Get-Content -Raw -LiteralPath $waiverPath | ConvertFrom-Json
    $waiver.reviewer = $null
    $waiver.PSObject.Properties.Remove('reviewer')
    $waiver.gameplay_receipt_claimed = $false
    $waiver.written_release_authorization.path = $invalidAuthorizationPath
    $waiver.written_release_authorization.sha256 = (Get-FileHash -LiteralPath $invalidAuthorizationPath -Algorithm SHA256).Hash.ToUpperInvariant()
    $waiver.written_release_authorization.record_sha256 = [string]$authorization.record_sha256
    $waiverMap = ConvertTo-MIRReleaseOrderedMap -Object $waiver
    $waiverMap.Remove('attestation_sha256')
    $waiverMap.attestation_sha256 = Get-MIRReleaseTextSha256 -Text ($waiverMap | ConvertTo-Json -Depth 40 -Compress)
    [IO.File]::WriteAllText($waiverPath, ($waiverMap | ConvertTo-Json -Depth 40 -Compress) + "`n", [Text.UTF8Encoding]::new($false))
    Assert-MIRManualReleaseReviewReject -Action { Test-MIRManualReleaseAttestation -RepoRoot $RepoRoot -Path $waiverPath -Candidate $candidate -FactorioBin $factorio -ExpectedSourceCommit ('a' * 40) -ExpectedFactorioVersion '2.1' } -Pattern '\[mir-manual-review-waiver-authorization\]' -Code 'technical-acceptance-claim-rejected'
  } finally {
    Set-Item Function:Get-MIRReleaseFactorioVersion -Value $factorioVersionReader
  }
  Write-Output "MIR-MANUAL-RELEASE-WRITTEN-WAIVER-PASSED fixture=$root"
  return
}

foreach ($required in @('Candidate','FactorioBin','ExpectedSourceCommit','ExpectedFactorioVersion')) {
  if ([string]::IsNullOrWhiteSpace([string](Get-Variable -Name $required -ValueOnly))) { throw "[mir-manual-release-review-input] $required" }
}
$result = Test-MIRManualReleaseAttestation -RepoRoot $RepoRoot -Path $Path -Candidate $Candidate `
  -FactorioBin $FactorioBin -ExpectedSourceCommit $ExpectedSourceCommit `
  -ExpectedFactorioVersion $ExpectedFactorioVersion
Write-Host "[ok] MIR manual release requirement validated ($($result.disposition)): $($result.sha256)"
