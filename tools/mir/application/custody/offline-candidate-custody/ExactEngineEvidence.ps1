function Assert-MIR4ExactEngineQualificationEvidenceBundleV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$EvidenceBundlePath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$CandidatePlanPath,
    [Parameter(Mandatory)]$Admission,
    [Parameter(Mandatory)][string]$ExactEngineExecutablePath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TrustedPublicKeyPath,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [string]$SchemaRoot = ""
  )

  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemas = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $bundlePath = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $EvidenceBundlePath `
    -Label "Exact-engine qualification evidence bundle"
  $scratch = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $ScratchRoot `
    -Label "Exact-engine evidence verification scratch root"
  if (-not [IO.Path]::IsPathRooted($ExactEngineExecutablePath) -or
      -not (Test-Path -LiteralPath $ExactEngineExecutablePath -PathType Leaf)) {
    throw "Exact-engine qualification requires an explicit existing engine executable path."
  }
  $engineExecutable = (Resolve-Path -LiteralPath $ExactEngineExecutablePath).Path
  $evidence = Assert-MIR4BootstrapRecordFileV1 -Path $bundlePath `
    -SchemaPath (Join-Path $schemas "mir4-exact-engine-qualification-evidence-bundle.schema.json")
  if (-not (Test-MIR4BootstrapRecordHash -Record $evidence.payload) -or
      [string]$evidence.payload.record_sha256 -cne [string]$evidence.signature.payload_record_sha256 -or
      [string]$evidence.payload.producer.identity -cne [string]$evidence.signature.identity -or
      [string]$evidence.payload.producer.namespace -cne [string]$evidence.signature.namespace) {
    throw "Exact-engine qualification evidence payload or signature binding is invalid."
  }

  $manifestBinding = New-MIR4CustodyRecordBindingV1 -Role "candidate-manifest" `
    -Record $Admission.manifest -Path $CandidateManifestPath
  $planBinding = New-MIR4CustodyRecordBindingV1 -Role "candidate-plan" `
    -Record $Admission.plan -Path $CandidatePlanPath
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $evidence.payload.candidate_manifest) -cne
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifestBinding) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $evidence.payload.candidate_plan) -cne
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $planBinding) -or
      [string]$evidence.payload.candidate.target_id -cne [string]$Admission.target.target_id -or
      [string]$evidence.payload.candidate.distribution_version -cne [string]$Admission.projection.distribution_version -or
      [string]$evidence.payload.candidate.archive_name -cne [string]$Admission.archive_name -or
      [string]$evidence.payload.candidate.archive_sha256 -cne [string]$Admission.manifest.local_distribution.archive_sha256 -or
      [long]$evidence.payload.candidate.bytes -ne [long]$Admission.manifest.local_distribution.bytes -or
      [string]$evidence.payload.engine.version -cne [string]$Admission.target.engine_lock.version -or
      [string]$evidence.payload.engine.executable_sha256 -cne [string]$Admission.target.engine_lock.executable_sha256 -or
      (Get-MIR4Sha256File -Path $engineExecutable) -cne [string]$Admission.target.engine_lock.executable_sha256 -or
      -not [bool]$evidence.payload.engine.network_denied) {
    throw "Exact-engine qualification evidence does not bind the admitted f210 candidate, plan, and engine executable."
  }

  $observations = @($evidence.payload.observations)
  $observationIds = @($observations | ForEach-Object { [string]$_.id })
  if (($observationIds -join "|") -cne ($script:MIR4ExactEngineObservationIdsV1 -join "|") -or
      @($observations | Where-Object { [string]$_.status -cne "passed" }).Count -gt 0) {
    throw "Exact-engine qualification evidence must contain the exact ordered passed observation set."
  }
  $bundleRoot = Split-Path -Parent $bundlePath
  $pathComparer = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    [StringComparer]::OrdinalIgnoreCase
  } else { [StringComparer]::Ordinal }
  $artifactPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]$pathComparer)
  foreach ($observation in $observations) {
    $relative = [string]$observation.result_artifact.relative_path
    $nativeRelative = $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $artifactPath = [IO.Path]::GetFullPath((Join-Path $bundleRoot $nativeRelative))
    if (-not (Test-MIR4CustodyDescendantPathV1 -Root $bundleRoot -Path $artifactPath) -or
        -not $artifactPaths.Add($artifactPath)) {
      throw "Exact-engine observation artifacts must be distinct descendants of the evidence bundle directory."
    }
    $artifactPath = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $artifactPath `
      -Label "Exact-engine observation artifact"
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf) -or
        (Get-MIR4Sha256File -Path $artifactPath) -cne [string]$observation.result_artifact.sha256 -or
        [long](Get-Item -LiteralPath $artifactPath).Length -ne [long]$observation.result_artifact.bytes) {
      throw "Exact-engine observation artifact bytes do not match the signed evidence bundle: $relative"
    }
  }

  if (-not (Test-Path -LiteralPath $scratch -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
  }
  $workRoot = Join-Path $scratch ("exact-engine-verify-" + [guid]::NewGuid().ToString("N"))
  $null = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $workRoot `
    -Label "Exact-engine evidence verification work root"
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
  try {
    $payloadPath = Join-Path $workRoot "payload.json"
    $null = Write-MIR4CustodyRecordV1 -Record $evidence.payload -Path $payloadPath
    $signatureBytes = [Convert]::FromBase64String([string]$evidence.signature.signature_base64)
    if ((Get-MIR4Sha256Bytes -Bytes $signatureBytes) -cne [string]$evidence.signature.signature_sha256) {
      throw "Exact-engine evidence signature bytes do not match their signed digest."
    }
    $signaturePath = Join-Path $workRoot "payload.json.sig"
    [IO.File]::WriteAllBytes($signaturePath, $signatureBytes)
    $embeddedPublicKeyPath = Join-Path $workRoot "embedded.pub"
    [IO.File]::WriteAllText(
      $embeddedPublicKeyPath,
      ([string]$evidence.payload.producer.public_key) + "`n",
      [Text.UTF8Encoding]::new($false)
    )
    $trustedFingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath `
      -PublicKeyPath $TrustedPublicKeyPath
    $embeddedFingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath `
      -PublicKeyPath $embeddedPublicKeyPath
    if ($trustedFingerprint -cne [string]$evidence.payload.producer.public_key_fingerprint -or
        $embeddedFingerprint -cne $trustedFingerprint -or
        -not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath `
          -PublicKeyPath $TrustedPublicKeyPath -Identity ([string]$evidence.signature.identity) `
          -Namespace $script:MIR4ExactEngineEvidenceNamespaceV1 -PayloadPath $payloadPath `
          -SignaturePath $signaturePath -ScratchRoot (Join-Path $workRoot "independent"))) {
      throw "Exact-engine qualification evidence is not signed by the explicit trusted producer key."
    }
    return $evidence
  } finally {
    if (Test-MIR4CustodyDescendantPathV1 -Root $scratch -Path $workRoot) {
      if (Test-Path -LiteralPath $workRoot -PathType Container) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
      }
    }
  }
}
