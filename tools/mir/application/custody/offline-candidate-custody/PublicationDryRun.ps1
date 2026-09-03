function New-MIR4PublicationDryRunBundleV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidatePath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$CandidatePlanPath,
    [Parameter(Mandatory)][string]$ExactEngineEvidenceBundlePath,
    [Parameter(Mandatory)][string]$ExactEngineExecutablePath,
    [Parameter(Mandatory)][string]$QualificationRecordPath,
    [Parameter(Mandatory)][string]$ReviewRecordPath,
    [Parameter(Mandatory)][string]$SealPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExactEngineTrustedPublicKeyPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TrustedPublicKeyPath,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [Parameter(Mandatory)][string]$CandidateId,
    [Parameter(Mandatory)][string]$TargetId,
    [Parameter(Mandatory)][string]$DistributionVersion,
    [Parameter(Mandatory)][string]$SourceVersion,
    [Parameter(Mandatory)][string]$SourceTag,
    [Parameter(Mandatory)][string]$DistributionTag,
    [Parameter(Mandatory)][string]$ReleaseTitle,
    [string[]]$Channels = @("github", "mod-portal"),
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$SchemaRoot = "",
    [string]$Mode = "dry-run"
  )

  Assert-MIR4OfflineCustodyModeV1 -Mode $Mode -Allowed "dry-run"
  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemaDirectory = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $output = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $OutputPath -Label "Publication dry-run bundle"
  $candidate = (Resolve-Path -LiteralPath $CandidatePath).Path
  if ($CandidateId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw "Invalid MIR 4 candidate ID." }
  $inputs = Get-MIR4CustodySealInputsV1 -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath `
    -CandidatePlanPath $CandidatePlanPath -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
    -ExactEngineExecutablePath $ExactEngineExecutablePath -QualificationRecordPath $QualificationRecordPath `
    -ReviewRecordPath $ReviewRecordPath -CandidatePath $candidate -SshKeygenPath $SshKeygenPath `
    -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
    -EvidenceVerificationScratchRoot (Join-Path $ScratchRoot "exact-engine-inputs") -SchemaRoot $schemaDirectory
  if (-not (Test-MIR4OfflineSealV1 -RepoRoot $repo -SealPath $SealPath -CandidatePath $candidate `
      -CandidateManifestPath $CandidateManifestPath `
      -CandidatePlanPath $CandidatePlanPath -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
      -ExactEngineExecutablePath $ExactEngineExecutablePath -QualificationRecordPath $QualificationRecordPath `
      -ReviewRecordPath $ReviewRecordPath -SshKeygenPath $SshKeygenPath `
      -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
      -TrustedPublicKeyPath $TrustedPublicKeyPath -ScratchRoot $ScratchRoot -SchemaRoot $schemaDirectory)) {
    throw "Publication dry-run generation requires an explicitly trust-anchored offline seal."
  }
  $seal = Assert-MIR4BootstrapRecordFileV1 -Path $SealPath `
    -SchemaPath (Join-Path $schemaDirectory "mir4-offline-seal.schema.json")
  $projection = $inputs.admission.projection
  if ($CandidateId -cne [string]$seal.payload.candidate.candidate_id -or
      $TargetId -cne [string]$projection.target_id -or
      $DistributionVersion -cne [string]$projection.distribution_version -or
      $SourceVersion -cne [string]$projection.source_version -or
      $SourceTag -cne [string]$projection.source_tag -or
      $DistributionTag -cne [string]$projection.distribution_tag) {
    throw "Publication dry-run identity does not match the admitted current V2 f210 projection."
  }
  $channelSet = @($Channels | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  if ($channelSet.Count -eq 0 -or @($channelSet | Where-Object { $_ -notin @("github", "mod-portal") }).Count -gt 0) {
    throw "Publication dry-run channels must be github and/or mod-portal."
  }
  $archiveName = [IO.Path]::GetFileName($candidate)
  $archiveSha = Get-MIR4Sha256File -Path $candidate
  $archiveBytes = (Get-Item -LiteralPath $candidate).Length
  if ($archiveName -cne [string]$projection.package_name -or
      $archiveSha -cne [string]$seal.payload.candidate.archive_sha256 -or
      [long]$archiveBytes -ne [long]$seal.payload.candidate.bytes) {
    throw "Publication dry-run candidate bytes do not match the trust-anchored seal."
  }
  $channelRequests = @(
    foreach ($channel in $channelSet) {
      [pscustomobject][ordered]@{
        channel = $channel
        operation = "describe-request-only"
        asset_name = $archiveName
        expected_sha256 = $archiveSha
        mutation_allowed = $false
      }
    }
  )
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = "MIR4PublicationDryRunBundleV1"
    canonicalization = $script:MIR4BootstrapCanonicalizationV1
    mode = "dry-run"
    mutating = $false
    network_required = $false
    apply_allowed = $false
    publication_authority = $false
    seal = [pscustomobject][ordered]@{
      kind = [string]$seal.kind
      record_sha256 = [string]$seal.record_sha256
      file_sha256 = Get-MIR4Sha256File -Path $SealPath
    }
    source_identity = [pscustomobject][ordered]@{
      version = $SourceVersion
      proposed_tag = $SourceTag
    }
    distribution_identity = [pscustomobject][ordered]@{
      target_id = $TargetId
      version = $DistributionVersion
      proposed_tag = $DistributionTag
    }
    identity_authorities = $inputs.admission.identity_authorities
    candidate = [pscustomobject][ordered]@{
      candidate_id = $CandidateId
      target_id = $TargetId
      distribution_version = $DistributionVersion
      archive_name = $archiveName
      archive_sha256 = $archiveSha
      bytes = [long]$archiveBytes
    }
    release = [pscustomobject][ordered]@{
      title = $ReleaseTitle
      asset_name = $archiveName
      asset_sha256 = $archiveSha
    }
    channel_requests = $channelRequests
    rollback = [pscustomobject][ordered]@{
      partial_publication_policy = "not-applicable-no-mutation"
      mutation_count = 0
    }
    readback_verification = @(
      [pscustomobject][ordered]@{
        id = "candidate-sha256"
        operation = "sha256"
        subject = $archiveName
        expected = $archiveSha
      },
      [pscustomobject][ordered]@{
        id = "candidate-byte-count"
        operation = "byte-count"
        subject = $archiveName
        expected = [long]$archiveBytes
      }
    )
  }
  $written = Write-MIR4CustodyRecordV1 -Record $record -Path $output
  $schema = Join-Path $schemaDirectory "mir4-publication-dry-run-bundle.schema.json"
  $null = Assert-MIR4BootstrapRecordFileV1 -Path $output -SchemaPath $schema
  return $written
}

function Assert-MIR4PublicationDryRunForSealV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SealPath,
    [Parameter(Mandatory)][string]$PublicationDryRunBundlePath,
    [Parameter(Mandatory)]$Seal,
    [Parameter(Mandatory)]$Admission,
    [string]$SchemaRoot = ""
  )

  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemas = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $publication = Assert-MIR4BootstrapRecordFileV1 -Path $PublicationDryRunBundlePath `
    -SchemaPath (Join-Path $schemas "mir4-publication-dry-run-bundle.schema.json")
  if ([string]$publication.mode -cne "dry-run" -or $publication.mutating -or
      $publication.apply_allowed -or $publication.publication_authority -or
      [string]$publication.seal.record_sha256 -cne [string]$Seal.record_sha256 -or
      [string]$publication.seal.file_sha256 -cne (Get-MIR4Sha256File -Path $SealPath)) {
    throw "Publication dry-run does not bind the supplied non-mutating offline seal."
  }
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $publication.candidate) -cne
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $Seal.payload.candidate) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $publication.source_identity) -cne
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $Seal.payload.source_identity) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $publication.distribution_identity) -cne
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $Seal.payload.distribution_identity) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $publication.identity_authorities) -cne
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $Admission.identity_authorities)) {
    throw "Publication dry-run identity does not match the admitted sealed candidate."
  }
  $candidateName = [string]$Seal.payload.candidate.archive_name
  $candidateSha = [string]$Seal.payload.candidate.archive_sha256
  $candidateBytes = [long]$Seal.payload.candidate.bytes
  if ([string]$publication.release.asset_name -cne $candidateName -or
      [string]$publication.release.asset_sha256 -cne $candidateSha) {
    throw "Publication dry-run release identity does not bind the sealed candidate."
  }
  $channelNames = @($publication.channel_requests | ForEach-Object { [string]$_.channel })
  $sortedChannelNames = @($channelNames | Sort-Object -Unique)
  if (($channelNames -join "|") -cne ($sortedChannelNames -join "|") -or
      @($publication.channel_requests | Where-Object {
        [string]$_.asset_name -cne $candidateName -or [string]$_.expected_sha256 -cne $candidateSha -or [bool]$_.mutation_allowed
      }).Count -gt 0) {
    throw "Publication dry-run channel requests are not canonical candidate-bound descriptions."
  }
  $shaReadback = @($publication.readback_verification | Where-Object { [string]$_.id -ceq "candidate-sha256" })
  $byteReadback = @($publication.readback_verification | Where-Object { [string]$_.id -ceq "candidate-byte-count" })
  if ($shaReadback.Count -ne 1 -or $byteReadback.Count -ne 1 -or
      [string]$shaReadback[0].operation -cne "sha256" -or [string]$shaReadback[0].subject -cne $candidateName -or
      [string]$shaReadback[0].expected -cne $candidateSha -or [string]$byteReadback[0].operation -cne "byte-count" -or
      [string]$byteReadback[0].subject -cne $candidateName -or [long]$byteReadback[0].expected -ne $candidateBytes) {
    throw "Publication dry-run readback verification is incomplete or stale."
  }
  return $publication
}

function Assert-MIR4PublicationDryRunPairV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SealPath,
    [Parameter(Mandatory)][string]$PublicationDryRunBundlePathA,
    [Parameter(Mandatory)][string]$PublicationDryRunBundlePathB,
    [Parameter(Mandatory)]$Seal,
    [Parameter(Mandatory)]$Admission,
    [string]$SchemaRoot = ""
  )

  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemas = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $pathA = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $PublicationDryRunBundlePathA `
    -Label "Publication dry-run bundle A"
  $pathB = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $PublicationDryRunBundlePathB `
    -Label "Publication dry-run bundle B"
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  if ([string]::Equals([IO.Path]::GetFullPath($pathA), [IO.Path]::GetFullPath($pathB), $comparison)) {
    throw "Publication dry-run idempotence requires two independently written bundle paths."
  }

  $runA = Assert-MIR4PublicationDryRunForSealV1 -RepoRoot $repo -SealPath $SealPath `
    -PublicationDryRunBundlePath $pathA -Seal $Seal -Admission $Admission -SchemaRoot $schemas
  $runB = Assert-MIR4PublicationDryRunForSealV1 -RepoRoot $repo -SealPath $SealPath `
    -PublicationDryRunBundlePath $pathB -Seal $Seal -Admission $Admission -SchemaRoot $schemas
  $canonicalA = ConvertTo-MIR4BootstrapCanonicalJson -Value $runA
  $canonicalB = ConvertTo-MIR4BootstrapCanonicalJson -Value $runB
  $fileShaA = Get-MIR4Sha256File -Path $pathA
  $fileShaB = Get-MIR4Sha256File -Path $pathB
  if ($canonicalA -cne $canonicalB -or
      [string]$runA.record_sha256 -cne [string]$runB.record_sha256 -or
      $fileShaA -cne $fileShaB) {
    throw "The independently written publication dry-run bundles are not canonically and byte-identical."
  }

  $bindings = @(
    [pscustomobject][ordered]@{
      run_id = "A"
      kind = [string]$runA.kind
      record_sha256 = [string]$runA.record_sha256
      file_sha256 = $fileShaA
    },
    [pscustomobject][ordered]@{
      run_id = "B"
      kind = [string]$runB.kind
      record_sha256 = [string]$runB.record_sha256
      file_sha256 = $fileShaB
    }
  )
  return [pscustomobject][ordered]@{
    records = @($runA, $runB)
    bindings = $bindings
  }
}
