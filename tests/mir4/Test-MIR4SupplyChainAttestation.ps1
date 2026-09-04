# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$SshKeygenPath = 'C:/Windows/System32/OpenSSH/ssh-keygen.exe'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/SupplyChainAttestation.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')

function Assert-MIR4SupplyChainAttestationTest {
  param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Diagnostic)
  if (-not $Condition) { throw "[$Diagnostic]" }
}

$packageBefore = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$testRoot = Join-Path $repo ('build/results/mir4-t15/tests/supply-chain-attestation-' + [guid]::NewGuid().ToString('N'))
$privateKey = Join-Path $testRoot 'keys/proof'
$publicKey = $privateKey + '.pub'
$otherPrivateKey = Join-Path $testRoot 'other-keys/proof'
$otherPublicKey = $otherPrivateKey + '.pub'
$scratchRoot = Join-Path $testRoot 'scratch'
$attestationPath = Join-Path $testRoot 'supply-chain-attestation.json'
$tamperedPath = Join-Path $testRoot 'supply-chain-attestation-tampered.json'
$identity = 'mir4-t15-attestation-test'
$workflowRef = 'refs/heads/codex/mir4-t15-supply-chain-preservation'

try {
  $null = New-MIR4ProofOnlyEd25519KeyPairV1 -RepoRoot $repo -SshKeygenPath $SshKeygenPath -PrivateKeyPath $privateKey -PublicKeyPath $publicKey -Identity $identity
  $null = New-MIR4ProofOnlyEd25519KeyPairV1 -RepoRoot $repo -SshKeygenPath $SshKeygenPath -PrivateKeyPath $otherPrivateKey -PublicKeyPath $otherPublicKey -Identity 'mir4-t15-other-proof'

  $inventory = New-MIR4ComponentInventoryV1 -RepoRoot $repo
  $provenance = New-MIR4SlsaProvenanceV1 -Inventory $inventory
  Assert-MIR4SupplyChainAttestationTest (
    Test-MIR4SupplyChainProvenanceBindingV1 -Inventory $inventory -SlsaProvenance $provenance -RepoRoot $repo
  ) 'mir4-supply-chain-attestation-provenance-binding'

  $attestation = New-MIR4SupplyChainAttestationV1 -RepoRoot $repo -Inventory $inventory -SlsaProvenance $provenance -SshKeygenPath $SshKeygenPath -PrivateKeyPath $privateKey -PublicKeyPath $publicKey -Identity $identity -ScratchRoot $scratchRoot -OutputPath $attestationPath -WorkflowRef $workflowRef
  $provenanceSha256 = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $provenance)
  $subject = @($provenance.subject | Where-Object { [string]$_.name -ceq 'mir4-player-f210' })[0]
  $verification = @{
    RepoRoot = $repo
    AttestationPath = $attestationPath
    SshKeygenPath = $SshKeygenPath
    TrustedPublicKeyPath = $publicKey
    ScratchRoot = (Join-Path $scratchRoot 'verify')
    ExpectedSourceCommit = [string]$inventory.source.commit
    ExpectedSourceTree = [string]$inventory.source.tree
    ExpectedWorkflowRef = $workflowRef
    ExpectedInventoryRecordSha256 = [string]$inventory.record_sha256
    ExpectedProvenanceSha256 = $provenanceSha256
    ExpectedSubjectName = [string]$subject.name
    ExpectedSubjectSha256 = [string]$subject.digest.sha256
    ExpectedTarget = 'f210'
  }
  Assert-MIR4SupplyChainAttestationTest (
    Test-MIR4SupplyChainAttestationV1 @verification
  ) 'mir4-supply-chain-attestation-valid'
  $verification.ExpectedTarget = 'f200'
  Assert-MIR4SupplyChainAttestationTest (
    Test-MIR4SupplyChainAttestationV1 @verification
  ) 'mir4-supply-chain-attestation-f200-binding'

  $negativeCases = @(
    @{ name = 'source-commit'; parameters = @{ ExpectedSourceCommit = ('0' * 40) } },
    @{ name = 'source-tree'; parameters = @{ ExpectedSourceTree = ('0' * 40) } },
    @{ name = 'workflow'; parameters = @{ ExpectedWorkflowRef = 'refs/heads/wrong' } },
    @{ name = 'inventory'; parameters = @{ ExpectedInventoryRecordSha256 = ('0' * 64) } },
    @{ name = 'provenance'; parameters = @{ ExpectedProvenanceSha256 = ('0' * 64) } },
    @{ name = 'subject'; parameters = @{ ExpectedSubjectSha256 = ('0' * 64) } },
    @{ name = 'target'; parameters = @{ ExpectedTarget = 'f110' } }
  )
  foreach ($case in $negativeCases) {
    $parameters = @{} + $verification
    foreach ($entry in $case.parameters.GetEnumerator()) {
      $parameters[[string]$entry.Key] = $entry.Value
    }
    Assert-MIR4SupplyChainAttestationTest (
      -not (Test-MIR4SupplyChainAttestationV1 @parameters)
    ) "mir4-supply-chain-attestation-negative-$($case.name)"
  }

  $fingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKey
  $revokedParameters = @{} + $verification
  $revokedParameters.RevokedFingerprints = @($fingerprint)
  Assert-MIR4SupplyChainAttestationTest (
    -not (Test-MIR4SupplyChainAttestationV1 @revokedParameters)
  ) 'mir4-supply-chain-attestation-revoked-key'

  $wrongTrustParameters = @{} + $verification
  $wrongTrustParameters.TrustedPublicKeyPath = $otherPublicKey
  Assert-MIR4SupplyChainAttestationTest (
    -not (Test-MIR4SupplyChainAttestationV1 @wrongTrustParameters)
  ) 'mir4-supply-chain-attestation-wrong-trusted-root'

  $tampered = (ConvertTo-MIR4BootstrapCanonicalJson -Value $attestation) | ConvertFrom-Json -Depth 100 -DateKind String
  $tampered.payload.targets[0].sha256 = '0' * 64
  $tampered.payload.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $tampered.payload
  $tampered.signature.payload_record_sha256 = [string]$tampered.payload.record_sha256
  $tampered.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $tampered
  Write-MIR4SupplyChainRecord -Record $tampered -Path $tamperedPath
  $tamperedParameters = @{} + $verification
  $tamperedParameters.AttestationPath = $tamperedPath
  Assert-MIR4SupplyChainAttestationTest (
    -not (Test-MIR4SupplyChainAttestationV1 @tamperedParameters)
  ) 'mir4-supply-chain-attestation-signed-payload-tamper'

  $badProvenance = (ConvertTo-MIR4BootstrapCanonicalJson -Value $provenance) | ConvertFrom-Json -Depth 100 -DateKind String
  $badProvenance.subject[0].digest.sha256 = '0' * 64
  Assert-MIR4SupplyChainAttestationTest (
    -not (Test-MIR4SupplyChainProvenanceBindingV1 -Inventory $inventory -SlsaProvenance $badProvenance -RepoRoot $repo)
  ) 'mir4-supply-chain-attestation-provenance-subject-tamper'

  $attestationText = ConvertTo-MIR4BootstrapCanonicalJson -Value $attestation
  Assert-MIR4SupplyChainAttestationTest (
    $attestationText -cnotmatch [regex]::Escape($privateKey) -and
    $attestationText -cnotmatch '(?i)(?:OPENSSH PRIVATE KEY|passphrase|private_key_path|mod_portal_token)'
  ) 'mir4-supply-chain-attestation-private-material-leak'
  $packageFingerprint = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
  Assert-MIR4SupplyChainAttestationTest (
    $packageFingerprint -ceq $packageBefore
  ) 'mir4-supply-chain-attestation-package-non-interference'

  [pscustomobject][ordered]@{
    status = 'passed'
    attestation_kind = [string]$attestation.kind
    attestation_record_sha256 = [string]$attestation.record_sha256
    source_commit = [string]$inventory.source.commit
    source_tree = [string]$inventory.source.tree
    subjects = @($attestation.payload.subjects).Count
    targets = @($attestation.payload.targets | ForEach-Object { [string]$_.target })
    revoked_key_rejected = $true
    tampered_payload_rejected = $true
    private_key_committed = [bool]$attestation.payload.signing_provider.private_key_committed
    publication_authority = [bool]$attestation.publication_authority
    package_source_sha256 = $packageFingerprint
  }
} finally {
  $buildRoot = Join-Path $repo 'build'
  if ((Test-MIR4CustodyDescendantPathV1 -Root $buildRoot -Path $testRoot) -and
      (Test-Path -LiteralPath $testRoot -PathType Container)) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}
