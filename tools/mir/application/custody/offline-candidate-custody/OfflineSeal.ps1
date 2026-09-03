function New-MIR4OfflineSealV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidatePath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$CandidatePlanPath,
    [Parameter(Mandatory)][string]$ExactEngineEvidenceBundlePath,
    [Parameter(Mandatory)][string]$ExactEngineExecutablePath,
    [Parameter(Mandatory)][string]$QualificationRecordPath,
    [Parameter(Mandatory)][string]$ReviewRecordPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExactEngineTrustedPublicKeyPath,
    [Parameter(Mandatory)][string]$PrivateKeyPath,
    [Parameter(Mandatory)][string]$PublicKeyPath,
    [Parameter(Mandatory)][string]$Identity,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$SchemaRoot = "",
    [string]$Mode = "local-offline-proof"
  )

  Assert-MIR4OfflineCustodyModeV1 -Mode $Mode -Allowed "local-offline-proof"
  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemaDirectory = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $output = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $OutputPath -Label "Offline candidate seal"
  $scratch = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $ScratchRoot -Label "Offline seal scratch root"
  $private = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $PrivateKeyPath -Label "Proof-only private key"
  $public = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $PublicKeyPath -Label "Proof-only public key"
  if (-not (Test-Path -LiteralPath $private -PathType Leaf)) { throw "Proof-only private key is missing." }
  $null = Get-MIR4OpenSshPublicKeyLineV1 -PublicKeyPath $public

  $sealSchema = Join-Path $schemaDirectory "mir4-offline-seal.schema.json"
  $inputs = Get-MIR4CustodySealInputsV1 -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath `
    -CandidatePlanPath $CandidatePlanPath -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
    -ExactEngineExecutablePath $ExactEngineExecutablePath -QualificationRecordPath $QualificationRecordPath `
    -ReviewRecordPath $ReviewRecordPath -CandidatePath $CandidatePath -SshKeygenPath $SshKeygenPath `
    -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
    -EvidenceVerificationScratchRoot (Join-Path $scratch "exact-engine-inputs") -SchemaRoot $schemaDirectory
  $qualification = $inputs.qualification
  $candidate = (Resolve-Path -LiteralPath $CandidatePath).Path
  $candidateSha = Get-MIR4Sha256File -Path $candidate
  $candidateBytes = (Get-Item -LiteralPath $candidate).Length
  $candidateName = [IO.Path]::GetFileName($candidate)
  if ($candidateSha -cne [string]$qualification.candidate.archive_sha256 -or
      [long]$candidateBytes -ne [long]$qualification.candidate.bytes -or
      [string]$qualification.candidate.archive_name -cne $candidateName) {
    throw "Candidate and admitted passed qualification identities do not match."
  }

  $provider = [pscustomobject][ordered]@{
    kind = "MIR4SigningProviderV1"
    algorithm = "ssh-ed25519"
    signature_format = "sshsig"
    implementation = "OpenSSH-ssh-keygen"
    executable_sha256 = Get-MIR4Sha256File -Path (Assert-MIR4ExplicitExecutableV1 -Path $SshKeygenPath)
    public_key = Get-MIR4OpenSshPublicKeyLineV1 -PublicKeyPath $public
    public_key_fingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $public
    identity = $Identity
    namespace = $script:MIR4OfflineSealNamespaceV1
    scope = "proof-only-local-r0"
    private_key_committed = $false
  }
  $payload = [pscustomobject][ordered]@{
    schema = 1
    kind = "MIR4OfflineSealPayloadV1"
    canonicalization = $script:MIR4BootstrapCanonicalizationV1
    seal_scope = "local-offline-proof-only"
    publication_authority = $false
    candidate = [pscustomobject][ordered]@{
      candidate_id = [string]$qualification.candidate.candidate_id
      target_id = [string]$qualification.candidate.target_id
      distribution_version = [string]$qualification.candidate.distribution_version
      archive_name = [string]$qualification.candidate.archive_name
      archive_sha256 = $candidateSha
      bytes = [long]$candidateBytes
    }
    source_identity = [pscustomobject][ordered]@{
      version = [string]$inputs.admission.projection.source_version
      proposed_tag = [string]$inputs.admission.projection.source_tag
    }
    distribution_identity = [pscustomobject][ordered]@{
      target_id = [string]$inputs.admission.projection.target_id
      version = [string]$inputs.admission.projection.distribution_version
      proposed_tag = [string]$inputs.admission.projection.distribution_tag
    }
    identity_authorities = $inputs.admission.identity_authorities
    bound_records = @($inputs.bound_records)
    signing_provider = $provider
  }

  if (-not (Test-Path -LiteralPath $scratch -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
  }
  $workRoot = Join-Path $scratch ("seal-" + [guid]::NewGuid().ToString("N"))
  $null = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $workRoot -Label "Offline seal work root"
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
  try {
    $payloadPath = Join-Path $workRoot "seal-payload.json"
    $payloadRecord = Write-MIR4CustodyRecordV1 -Record $payload -Path $payloadPath
    $signaturePath = "$payloadPath.sig"
    if (Test-Path -LiteralPath $signaturePath) { throw "Offline seal signature path is unexpectedly occupied." }
    $signResult = Invoke-MIR4OpenSshProcessV1 -SshKeygenPath $SshKeygenPath -Arguments @(
      "-Y", "sign", "-f", $private, "-n", $script:MIR4OfflineSealNamespaceV1, $payloadPath
    )
    if ($signResult.exit_code -ne 0 -or -not (Test-Path -LiteralPath $signaturePath -PathType Leaf)) {
      throw "OpenSSH failed to sign the MIR 4 offline seal payload."
    }
    $verifyScratch = Join-Path $workRoot "independent-verification"
    if (-not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $public `
        -Identity $Identity -Namespace $script:MIR4OfflineSealNamespaceV1 -PayloadPath $payloadPath `
        -SignaturePath $signaturePath -ScratchRoot $verifyScratch)) {
      throw "Independent OpenSSH verification rejected the new MIR 4 offline seal signature."
    }
    $signatureBytes = [IO.File]::ReadAllBytes($signaturePath)
    $seal = [pscustomobject][ordered]@{
      schema = 1
      kind = "MIR4OfflineSealV1"
      canonicalization = $script:MIR4BootstrapCanonicalizationV1
      status = "sealed-local-proof-only"
      publication_authority = $false
      payload = $payloadRecord
      signature = [pscustomobject][ordered]@{
        algorithm = "ssh-ed25519"
        format = "sshsig"
        identity = $Identity
        namespace = $script:MIR4OfflineSealNamespaceV1
        payload_record_sha256 = [string]$payloadRecord.record_sha256
        signature_sha256 = Get-MIR4Sha256Bytes -Bytes $signatureBytes
        signature_base64 = [Convert]::ToBase64String($signatureBytes)
      }
    }
    $sealRecord = Write-MIR4CustodyRecordV1 -Record $seal -Path $output
    $null = Assert-MIR4BootstrapRecordFileV1 -Path $output -SchemaPath $sealSchema
    if (-not (Test-MIR4OfflineSealV1 -RepoRoot $repo -SealPath $output -CandidatePath $candidate `
        -CandidateManifestPath $CandidateManifestPath -CandidatePlanPath $CandidatePlanPath `
        -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
        -ExactEngineExecutablePath $ExactEngineExecutablePath `
        -QualificationRecordPath $QualificationRecordPath -ReviewRecordPath $ReviewRecordPath `
        -SshKeygenPath $SshKeygenPath -TrustedPublicKeyPath $public `
        -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
        -ScratchRoot (Join-Path $scratch "verify-new-seal") -SchemaRoot $schemaDirectory)) {
      throw "The completed MIR 4 offline seal failed independent verification."
    }
    return $sealRecord
  } finally {
    if (Test-MIR4CustodyDescendantPathV1 -Root $scratch -Path $workRoot) {
      if (Test-Path -LiteralPath $workRoot -PathType Container) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
      }
    }
  }
}

function Test-MIR4OfflineSealV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SealPath,
    [Parameter(Mandatory)][string]$CandidatePath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$CandidatePlanPath,
    [Parameter(Mandatory)][string]$ExactEngineEvidenceBundlePath,
    [Parameter(Mandatory)][string]$ExactEngineExecutablePath,
    [Parameter(Mandatory)][string]$QualificationRecordPath,
    [Parameter(Mandatory)][string]$ReviewRecordPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExactEngineTrustedPublicKeyPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TrustedPublicKeyPath,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [string]$SchemaRoot = ""
  )

  try {
    $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
    $schemaDirectory = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
    $scratch = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $ScratchRoot -Label "Offline seal verification scratch root"
    $seal = Assert-MIR4BootstrapRecordFileV1 -Path $SealPath -SchemaPath (Join-Path $schemaDirectory "mir4-offline-seal.schema.json")
    $inputs = Get-MIR4CustodySealInputsV1 -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath `
      -CandidatePlanPath $CandidatePlanPath -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
      -ExactEngineExecutablePath $ExactEngineExecutablePath -QualificationRecordPath $QualificationRecordPath `
      -ReviewRecordPath $ReviewRecordPath -CandidatePath $CandidatePath -SshKeygenPath $SshKeygenPath `
      -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
      -EvidenceVerificationScratchRoot (Join-Path $scratch "exact-engine-inputs") -SchemaRoot $schemaDirectory
    $expectedSource = [pscustomobject][ordered]@{
      version = [string]$inputs.admission.projection.source_version
      proposed_tag = [string]$inputs.admission.projection.source_tag
    }
    $expectedDistribution = [pscustomobject][ordered]@{
      target_id = [string]$inputs.admission.projection.target_id
      version = [string]$inputs.admission.projection.distribution_version
      proposed_tag = [string]$inputs.admission.projection.distribution_tag
    }
    if (-not (Test-MIR4BootstrapRecordHash -Record $seal.payload) -or
        [string]$seal.payload.record_sha256 -cne [string]$seal.signature.payload_record_sha256 -or
        [string]$seal.signature.identity -cne [string]$seal.payload.signing_provider.identity -or
        [string]$seal.signature.namespace -cne [string]$seal.payload.signing_provider.namespace -or
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $seal.payload.candidate) -cne
          (ConvertTo-MIR4BootstrapCanonicalJson -Value $inputs.qualification.candidate) -or
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $seal.payload.source_identity) -cne
          (ConvertTo-MIR4BootstrapCanonicalJson -Value $expectedSource) -or
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $seal.payload.distribution_identity) -cne
          (ConvertTo-MIR4BootstrapCanonicalJson -Value $expectedDistribution) -or
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $seal.payload.identity_authorities) -cne
          (ConvertTo-MIR4BootstrapCanonicalJson -Value $inputs.admission.identity_authorities) -or
        (ConvertTo-MIR4BootstrapCanonicalJson -Value @($seal.payload.bound_records)) -cne
          (ConvertTo-MIR4BootstrapCanonicalJson -Value @($inputs.bound_records))) { return $false }
    $signatureBytes = [Convert]::FromBase64String([string]$seal.signature.signature_base64)
    if ((Get-MIR4Sha256Bytes -Bytes $signatureBytes) -cne [string]$seal.signature.signature_sha256) { return $false }

    if (-not (Test-Path -LiteralPath $scratch -PathType Container)) {
      New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    }
    $workRoot = Join-Path $scratch ("verify-" + [guid]::NewGuid().ToString("N"))
    $null = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $workRoot -Label "Offline seal verification work root"
    New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
    try {
      $payloadPath = Join-Path $workRoot "payload.json"
      $null = Write-MIR4CustodyRecordV1 -Record $seal.payload -Path $payloadPath
      $signaturePath = Join-Path $workRoot "payload.json.sig"
      [IO.File]::WriteAllBytes($signaturePath, $signatureBytes)
      $embeddedPublicKeyPath = Join-Path $workRoot "embedded.pub"
      [IO.File]::WriteAllText(
        $embeddedPublicKeyPath,
        ([string]$seal.payload.signing_provider.public_key) + "`n",
        [Text.UTF8Encoding]::new($false)
      )
      $trustedFingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath `
        -PublicKeyPath $TrustedPublicKeyPath
      $embeddedFingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath `
        -PublicKeyPath $embeddedPublicKeyPath
      if ($trustedFingerprint -cne [string]$seal.payload.signing_provider.public_key_fingerprint -or
          $embeddedFingerprint -cne $trustedFingerprint) {
        return $false
      }
      return Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $TrustedPublicKeyPath `
        -Identity ([string]$seal.signature.identity) -Namespace ([string]$seal.signature.namespace) `
        -PayloadPath $payloadPath -SignaturePath $signaturePath -ScratchRoot (Join-Path $workRoot "independent")
    } finally {
      if (Test-MIR4CustodyDescendantPathV1 -Root $scratch -Path $workRoot) {
        if (Test-Path -LiteralPath $workRoot -PathType Container) {
          Remove-Item -LiteralPath $workRoot -Recurse -Force
        }
      }
    }
  } catch {
    return $false
  }
}
