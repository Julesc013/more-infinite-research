function Restore-MIR4OfflineCandidateV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SealPath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$CandidatePlanPath,
    [Parameter(Mandatory)][string]$ExactEngineEvidenceBundlePath,
    [Parameter(Mandatory)][string]$ExactEngineExecutablePath,
    [Parameter(Mandatory)][string]$QualificationRecordPath,
    [Parameter(Mandatory)][string]$ReviewRecordPath,
    [Parameter(Mandatory)][string]$PublicationDryRunBundlePathA,
    [Parameter(Mandatory)][string]$PublicationDryRunBundlePathB,
    [Parameter(Mandatory)][string]$SourceCandidatePath,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$ReceiptPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExactEngineTrustedPublicKeyPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TrustedPublicKeyPath,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [string]$SchemaRoot = "",
    [string]$Mode = "restore"
  )

  Assert-MIR4OfflineCustodyModeV1 -Mode $Mode -Allowed "restore"
  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemaDirectory = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $output = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $OutputRoot -Label "Offline restoration output root"
  $receipt = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $ReceiptPath -Label "Offline restoration receipt"
  $scratch = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $ScratchRoot -Label "Offline restoration verification scratch root"
  if (Test-MIR4CustodyDescendantPathV1 -Root $output -Path $receipt) {
    throw "The restoration receipt must be outside the verified clean restoration output."
  }
  if (-not (Test-MIR4OfflineSealV1 -RepoRoot $repo -SealPath $SealPath -CandidatePath $SourceCandidatePath `
      -CandidateManifestPath $CandidateManifestPath -CandidatePlanPath $CandidatePlanPath `
      -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
      -ExactEngineExecutablePath $ExactEngineExecutablePath `
      -QualificationRecordPath $QualificationRecordPath -ReviewRecordPath $ReviewRecordPath `
      -SshKeygenPath $SshKeygenPath -TrustedPublicKeyPath $TrustedPublicKeyPath `
      -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
      -ScratchRoot $scratch -SchemaRoot $schemaDirectory)) {
    throw "Candidate restoration requires a valid offline seal."
  }
  $seal = Assert-MIR4BootstrapRecordFileV1 -Path $SealPath -SchemaPath (Join-Path $schemaDirectory "mir4-offline-seal.schema.json")
  $inputs = Get-MIR4CustodySealInputsV1 -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath `
    -CandidatePlanPath $CandidatePlanPath -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
    -ExactEngineExecutablePath $ExactEngineExecutablePath -QualificationRecordPath $QualificationRecordPath `
    -ReviewRecordPath $ReviewRecordPath -CandidatePath $SourceCandidatePath -SshKeygenPath $SshKeygenPath `
    -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
    -EvidenceVerificationScratchRoot (Join-Path $scratch "exact-engine-inputs") -SchemaRoot $schemaDirectory
  $publicationPair = Assert-MIR4PublicationDryRunPairV1 -RepoRoot $repo -SealPath $SealPath `
    -PublicationDryRunBundlePathA $PublicationDryRunBundlePathA `
    -PublicationDryRunBundlePathB $PublicationDryRunBundlePathB -Seal $seal `
    -Admission $inputs.admission -SchemaRoot $schemaDirectory
  $source = (Resolve-Path -LiteralPath $SourceCandidatePath).Path
  $sourceSha = Get-MIR4Sha256File -Path $source
  $sourceBytes = (Get-Item -LiteralPath $source).Length
  if ($sourceSha -cne [string]$seal.payload.candidate.archive_sha256 -or
      [long]$sourceBytes -ne [long]$seal.payload.candidate.bytes) {
    throw "Restoration source does not match the sealed candidate."
  }
  if (Test-Path -LiteralPath $output) {
    if (-not (Test-Path -LiteralPath $output -PathType Container)) { throw "Restoration output is not a directory." }
    if (@(Get-ChildItem -LiteralPath $output -Force).Count -ne 0) {
      throw "Restoration requires an existing empty directory or an absent output path."
    }
  } else {
    New-Item -ItemType Directory -Force -Path $output | Out-Null
  }
  $restoredPath = Join-Path $output ([string]$seal.payload.candidate.archive_name)
  [IO.File]::Copy($source, $restoredPath, $false)
  $restoredSha = Get-MIR4Sha256File -Path $restoredPath
  $restoredBytes = (Get-Item -LiteralPath $restoredPath).Length
  if ($restoredSha -cne $sourceSha -or [long]$restoredBytes -ne [long]$sourceBytes -or
      @(Get-ChildItem -LiteralPath $output -Recurse -File -Force).Count -ne 1) {
    throw "Restored candidate bytes or clean-output extent do not match the seal."
  }
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = "MIR4RestorationReceiptV1"
    canonicalization = $script:MIR4BootstrapCanonicalizationV1
    mode = "restore"
    status = "passed"
    publication_authority = $false
    output_was_empty = $true
    candidate = $seal.payload.candidate
    seal = [pscustomobject][ordered]@{
      kind = [string]$seal.kind
      record_sha256 = [string]$seal.record_sha256
      file_sha256 = Get-MIR4Sha256File -Path $SealPath
    }
    publication_dry_runs = @($publicationPair.bindings)
    source = [pscustomobject][ordered]@{
      archive_sha256 = $sourceSha
      bytes = [long]$sourceBytes
    }
    restored = [pscustomobject][ordered]@{
      archive_name = [IO.Path]::GetFileName($restoredPath)
      archive_sha256 = $restoredSha
      bytes = [long]$restoredBytes
    }
  }
  $written = Write-MIR4CustodyRecordV1 -Record $record -Path $receipt
  $null = Assert-MIR4BootstrapRecordFileV1 -Path $receipt -SchemaPath (Join-Path $schemaDirectory "mir4-restoration-receipt.schema.json")
  return $written
}

function New-MIR4EmergencyLaneCompletionRecordV1 {
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
    [Parameter(Mandatory)][string]$PublicationDryRunBundlePathA,
    [Parameter(Mandatory)][string]$PublicationDryRunBundlePathB,
    [Parameter(Mandatory)][string]$RestorationReceiptPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExactEngineTrustedPublicKeyPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TrustedPublicKeyPath,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$SchemaRoot = "",
    [string]$Mode = "record"
  )

  Assert-MIR4OfflineCustodyModeV1 -Mode $Mode -Allowed "record"
  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemaDirectory = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $output = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $OutputPath -Label "Emergency-lane completion record"
  if (-not (Test-MIR4OfflineSealV1 -RepoRoot $repo -SealPath $SealPath -CandidatePath $CandidatePath `
      -CandidateManifestPath $CandidateManifestPath -CandidatePlanPath $CandidatePlanPath `
      -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
      -ExactEngineExecutablePath $ExactEngineExecutablePath `
      -QualificationRecordPath $QualificationRecordPath -ReviewRecordPath $ReviewRecordPath `
      -SshKeygenPath $SshKeygenPath -TrustedPublicKeyPath $TrustedPublicKeyPath `
      -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
      -ScratchRoot $ScratchRoot -SchemaRoot $schemaDirectory)) {
    throw "Emergency-lane completion requires a valid offline seal."
  }
  $seal = Assert-MIR4BootstrapRecordFileV1 -Path $SealPath -SchemaPath (Join-Path $schemaDirectory "mir4-offline-seal.schema.json")
  $inputs = Get-MIR4CustodySealInputsV1 -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath `
    -CandidatePlanPath $CandidatePlanPath -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
    -ExactEngineExecutablePath $ExactEngineExecutablePath -QualificationRecordPath $QualificationRecordPath `
    -ReviewRecordPath $ReviewRecordPath -CandidatePath $CandidatePath -SshKeygenPath $SshKeygenPath `
    -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
    -EvidenceVerificationScratchRoot (Join-Path $ScratchRoot "exact-engine-inputs") -SchemaRoot $schemaDirectory
  $publicationPair = Assert-MIR4PublicationDryRunPairV1 -RepoRoot $repo -SealPath $SealPath `
    -PublicationDryRunBundlePathA $PublicationDryRunBundlePathA `
    -PublicationDryRunBundlePathB $PublicationDryRunBundlePathB -Seal $seal `
    -Admission $inputs.admission -SchemaRoot $schemaDirectory
  $restoration = Assert-MIR4BootstrapRecordFileV1 -Path $RestorationReceiptPath `
    -SchemaPath (Join-Path $schemaDirectory "mir4-restoration-receipt.schema.json")
  $sealedCandidateJson = ConvertTo-MIR4BootstrapCanonicalJson -Value $seal.payload.candidate
  $restoredCandidateJson = ConvertTo-MIR4BootstrapCanonicalJson -Value $restoration.candidate
  $expectedDryRunsJson = ConvertTo-MIR4BootstrapCanonicalJson -Value @($publicationPair.bindings)
  $restoredDryRunsJson = ConvertTo-MIR4BootstrapCanonicalJson -Value @($restoration.publication_dry_runs)
  if ([string]$restoration.status -cne "passed" -or
      [string]$restoration.seal.record_sha256 -cne [string]$seal.record_sha256 -or
      [string]$restoration.seal.file_sha256 -cne (Get-MIR4Sha256File -Path $SealPath) -or
      $restoredDryRunsJson -cne $expectedDryRunsJson -or
      $restoredCandidateJson -cne $sealedCandidateJson -or
      [string]$restoration.source.archive_sha256 -cne [string]$seal.payload.candidate.archive_sha256 -or
      [long]$restoration.source.bytes -ne [long]$seal.payload.candidate.bytes -or
      [string]$restoration.restored.archive_name -cne [string]$seal.payload.candidate.archive_name -or
      [string]$restoration.restored.archive_sha256 -cne [string]$seal.payload.candidate.archive_sha256 -or
      [long]$restoration.restored.bytes -ne [long]$seal.payload.candidate.bytes) {
    throw "Restoration receipt does not bind the supplied offline seal and candidate."
  }
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = "MIR4EmergencyLaneCompletionRecordV1"
    canonicalization = $script:MIR4BootstrapCanonicalizationV1
    status = "passed-local-proof-only"
    publication_authority = $false
    candidate = $seal.payload.candidate
    seal = [pscustomobject][ordered]@{
      kind = [string]$seal.kind
      record_sha256 = [string]$seal.record_sha256
      file_sha256 = Get-MIR4Sha256File -Path $SealPath
    }
    publication_dry_runs = @($publicationPair.bindings)
    restoration = [pscustomobject][ordered]@{
      kind = [string]$restoration.kind
      record_sha256 = [string]$restoration.record_sha256
      file_sha256 = Get-MIR4Sha256File -Path $RestorationReceiptPath
    }
  }
  $written = Write-MIR4CustodyRecordV1 -Record $record -Path $output
  $null = Assert-MIR4BootstrapRecordFileV1 -Path $output `
    -SchemaPath (Join-Path $schemaDirectory "mir4-emergency-lane-completion-record.schema.json")
  return $written
}
