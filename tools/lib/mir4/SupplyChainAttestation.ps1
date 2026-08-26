if (-not (Get-Command New-MIR4ComponentInventoryV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'SupplyChain.ps1')
}
if (-not (Get-Command Test-MIR4OpenSshSignatureV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'OfflineCandidateCustody.ps1')
}

$script:MIR4SupplyChainAttestationNamespaceV1 = 'mir4-supply-chain-attestation-v1'
$script:MIR4SupplyChainAttestationSchemaPathV1 = 'spec/schemas/mir4-supply-chain-attestation-v1.schema.json'

function Test-MIR4SupplyChainProvenanceBindingV1 {
  param(
    [Parameter(Mandatory)]$Inventory,
    [Parameter(Mandatory)]$SlsaProvenance,
    [Parameter(Mandatory)][string]$RepoRoot
  )

  try {
    if (-not (Test-MIR4ComponentInventoryV1 -Inventory $Inventory -RepoRoot $RepoRoot) -or
        -not (Test-MIR4SlsaProvenanceV1 -Statement $SlsaProvenance -RepoRoot $RepoRoot)) {
      return $false
    }
    $expectedSubjects = @(
      foreach ($component in $Inventory.components) {
        $digest = if ($null -ne $component.artifact) {
          [string]$component.artifact.sha256
        } else {
          [string]$component.content_root.sha256
        }
        [pscustomobject][ordered]@{
          name = [string]$component.component_id
          digest = [pscustomobject][ordered]@{ sha256 = $digest.ToLowerInvariant() }
        }
      }
    )
    if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $expectedSubjects) -cne
        (ConvertTo-MIR4BootstrapCanonicalJson -Value @($SlsaProvenance.subject))) {
      return $false
    }
    $expectedIds = @($Inventory.components | ForEach-Object { [string]$_.component_id })
    if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $expectedIds) -cne
        (ConvertTo-MIR4BootstrapCanonicalJson -Value @($SlsaProvenance.predicate.buildDefinition.externalParameters.component_ids))) {
      return $false
    }
    $gitDependencies = @(
      $SlsaProvenance.predicate.buildDefinition.resolvedDependencies |
        Where-Object { [string]$_.uri -like 'git+https://github.com/Julesc013/more-infinite-research@*' }
    )
    if ($gitDependencies.Count -ne 1 -or
        [string]$gitDependencies[0].uri -cne "git+https://github.com/Julesc013/more-infinite-research@$($Inventory.source.commit)" -or
        [string]$gitDependencies[0].digest.gitCommit -cne [string]$Inventory.source.commit -or
        [string]$gitDependencies[0].digest.gitTree -cne [string]$Inventory.source.tree) {
      return $false
    }
    $inventoryByproducts = @(
      $SlsaProvenance.predicate.runDetails.byproducts |
        Where-Object { [string]$_.name -ceq 'component-inventory.json' }
    )
    if ($inventoryByproducts.Count -ne 1 -or
        [string]$inventoryByproducts[0].digest.sha256 -cne ([string]$Inventory.record_sha256).ToLowerInvariant()) {
      return $false
    }
    $parameters = $SlsaProvenance.predicate.buildDefinition.internalParameters
    return [long]$parameters.source_date_epoch -eq [long]$Inventory.source.source_date_epoch -and
      [string]$parameters.archive_order -ceq [string]$Inventory.construction.archive_order -and
      [string]$parameters.archive_timestamp -ceq [string]$Inventory.construction.archive_timestamp -and
      [bool]$parameters.working_tree_clean -eq [bool]$Inventory.source.working_tree_clean
  } catch {
    return $false
  }
}

function New-MIR4SupplyChainAttestationV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Inventory,
    [Parameter(Mandatory)]$SlsaProvenance,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$PrivateKeyPath,
    [Parameter(Mandatory)][string]$PublicKeyPath,
    [Parameter(Mandatory)][string]$Identity,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$WorkflowRef,
    [string]$Mode = 'local-offline-proof'
  )

  Assert-MIR4OfflineCustodyModeV1 -Mode $Mode -Allowed 'local-offline-proof'
  $repo = Resolve-MIR4SupplyChainRepoRoot -RepoRoot $RepoRoot
  if (-not (Test-MIR4ComponentInventoryV1 -Inventory $Inventory -RepoRoot $repo)) {
    throw '[mir4-supply-chain-attestation-inventory]'
  }
  if (-not (Test-MIR4SupplyChainProvenanceBindingV1 -Inventory $Inventory -SlsaProvenance $SlsaProvenance -RepoRoot $repo)) {
    throw '[mir4-supply-chain-attestation-provenance]'
  }
  if ($WorkflowRef -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._/@:+-]{0,255}$') {
    throw '[mir4-supply-chain-attestation-workflow]'
  }
  $output = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $OutputPath -Label 'Supply-chain attestation'
  $scratch = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $ScratchRoot -Label 'Supply-chain attestation scratch root'
  $private = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $PrivateKeyPath -Label 'Proof-only attestation private key'
  $public = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $PublicKeyPath -Label 'Proof-only attestation public key'
  if (-not (Test-Path -LiteralPath $private -PathType Leaf)) {
    throw '[mir4-supply-chain-attestation-private-key-missing]'
  }
  $publicKey = Get-MIR4OpenSshPublicKeyLineV1 -PublicKeyPath $public
  $fingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $public
  $subjects = @(
    $SlsaProvenance.subject |
      ForEach-Object {
        [pscustomobject][ordered]@{
          name = [string]$_.name
          digest = [pscustomobject][ordered]@{ sha256 = [string]$_.digest.sha256 }
        }
      }
  )
  $targets = @(
    $Inventory.components |
      Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.target) } |
      ForEach-Object {
        $component = $_
        $subject = @($subjects | Where-Object { [string]$_.name -ceq [string]$component.component_id })
        if ($subject.Count -ne 1) {
          throw "[mir4-supply-chain-attestation-target-subject] $($component.component_id)"
        }
        [pscustomobject][ordered]@{
          component_id = [string]$component.component_id
          target = [string]$component.target
          version = [string]$component.version
          sha256 = [string]$subject[0].digest.sha256
        }
      }
  )
  $provider = [pscustomobject][ordered]@{
    kind = 'MIR4SigningProviderV1'
    algorithm = 'ssh-ed25519'
    signature_format = 'sshsig'
    implementation = 'OpenSSH-ssh-keygen'
    executable_sha256 = Get-MIR4Sha256File -Path (Assert-MIR4ExplicitExecutableV1 -Path $SshKeygenPath)
    public_key = $publicKey
    public_key_fingerprint = $fingerprint
    identity = $Identity
    namespace = $script:MIR4SupplyChainAttestationNamespaceV1
    scope = 'proof-only-local-t15'
    private_key_committed = $false
  }
  $payload = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4SupplyChainAttestationPayloadV1'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    predicate_type = 'https://more-infinite-research.invalid/attestations/supply-chain/v1'
    scope = 'local-offline-proof-only'
    publication_authority = $false
    source = [pscustomobject][ordered]@{
      commit = [string]$Inventory.source.commit
      tree = [string]$Inventory.source.tree
    }
    inventory = [pscustomobject][ordered]@{
      kind = [string]$Inventory.kind
      record_sha256 = [string]$Inventory.record_sha256
    }
    provenance = [pscustomobject][ordered]@{
      predicate_type = [string]$SlsaProvenance.predicateType
      sha256 = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $SlsaProvenance)
    }
    subjects = $subjects
    github_subjects = $subjects
    targets = $targets
    workflow = [pscustomobject][ordered]@{
      repository = 'Julesc013/more-infinite-research'
      ref = $WorkflowRef
      workflow = 'tools/commands/mir4/Invoke-MIR4SupplyChain.ps1'
    }
    trusted_root = [pscustomobject][ordered]@{
      root_id = 'mir4-t15-proof-root'
      public_key_fingerprint = $fingerprint
      status = 'proof-only-active'
    }
    revocation_snapshot = [pscustomobject][ordered]@{
      source_commit = [string]$Inventory.source.commit
      revoked_fingerprints = @()
    }
    signing_provider = $provider
  }

  if (-not (Test-Path -LiteralPath $scratch -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
  }
  $workRoot = Join-Path $scratch ('attestation-' + [guid]::NewGuid().ToString('N'))
  $null = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $workRoot -Label 'Supply-chain attestation work root'
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
  try {
    $payloadPath = Join-Path $workRoot 'attestation-payload.json'
    $payloadRecord = Write-MIR4CustodyRecordV1 -Record $payload -Path $payloadPath
    $signaturePath = $payloadPath + '.sig'
    $signResult = Invoke-MIR4OpenSshProcessV1 -SshKeygenPath $SshKeygenPath -Arguments @(
      '-Y', 'sign', '-f', $private, '-n', $script:MIR4SupplyChainAttestationNamespaceV1, $payloadPath
    )
    if ($signResult.exit_code -ne 0 -or -not (Test-Path -LiteralPath $signaturePath -PathType Leaf)) {
      throw '[mir4-supply-chain-attestation-sign]'
    }
    if (-not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $public -Identity $Identity -Namespace $script:MIR4SupplyChainAttestationNamespaceV1 -PayloadPath $payloadPath -SignaturePath $signaturePath -ScratchRoot (Join-Path $workRoot 'independent'))) {
      throw '[mir4-supply-chain-attestation-immediate-verification]'
    }
    $signatureBytes = [IO.File]::ReadAllBytes($signaturePath)
    $attestation = [pscustomobject][ordered]@{
      schema = 1
      kind = 'MIR4SupplyChainAttestationV1'
      canonicalization = 'MIR4BootstrapCanonicalJsonV1'
      status = 'attested-local-proof-only'
      publication_authority = $false
      payload = $payloadRecord
      signature = [pscustomobject][ordered]@{
        algorithm = 'ssh-ed25519'
        format = 'sshsig'
        identity = $Identity
        namespace = $script:MIR4SupplyChainAttestationNamespaceV1
        payload_record_sha256 = [string]$payloadRecord.record_sha256
        signature_sha256 = Get-MIR4Sha256Bytes -Bytes $signatureBytes
        signature_base64 = [Convert]::ToBase64String($signatureBytes)
      }
    }
    $written = Write-MIR4CustodyRecordV1 -Record $attestation -Path $output
    $schemaPath = Join-Path $repo $script:MIR4SupplyChainAttestationSchemaPathV1
    $null = Assert-MIR4BootstrapRecordFileV1 -Path $output -SchemaPath $schemaPath
    if (-not (Test-MIR4SupplyChainAttestationV1 -RepoRoot $repo -AttestationPath $output -SshKeygenPath $SshKeygenPath -TrustedPublicKeyPath $public -ScratchRoot (Join-Path $scratch 'verify-new') -ExpectedSourceCommit ([string]$Inventory.source.commit) -ExpectedSourceTree ([string]$Inventory.source.tree) -ExpectedWorkflowRef $WorkflowRef)) {
      throw '[mir4-supply-chain-attestation-independent-verification]'
    }
    return $written
  } finally {
    if (Test-MIR4CustodyDescendantPathV1 -Root $scratch -Path $workRoot) {
      if (Test-Path -LiteralPath $workRoot -PathType Container) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
      }
    }
  }
}

function Test-MIR4SupplyChainAttestationV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$AttestationPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$TrustedPublicKeyPath,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [string]$ExpectedSourceCommit,
    [string]$ExpectedSourceTree,
    [string]$ExpectedWorkflowRef,
    [string]$ExpectedInventoryRecordSha256,
    [string]$ExpectedProvenanceSha256,
    [string]$ExpectedSubjectName,
    [string]$ExpectedSubjectSha256,
    [string]$ExpectedTarget,
    [string[]]$RevokedFingerprints = @()
  )

  try {
    $repo = Resolve-MIR4SupplyChainRepoRoot -RepoRoot $RepoRoot
    $scratch = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $ScratchRoot -Label 'Supply-chain attestation verification scratch root'
    $schemaPath = Join-Path $repo $script:MIR4SupplyChainAttestationSchemaPathV1
    $attestation = Assert-MIR4BootstrapRecordFileV1 -Path $AttestationPath -SchemaPath $schemaPath
    if (-not (Test-MIR4BootstrapRecordHash -Record $attestation.payload) -or
        [bool]$attestation.publication_authority -or
        [bool]$attestation.payload.publication_authority -or
        [bool]$attestation.payload.signing_provider.private_key_committed) {
      return $false
    }
    $trustedKey = Get-MIR4OpenSshPublicKeyLineV1 -PublicKeyPath $TrustedPublicKeyPath
    $trustedFingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $TrustedPublicKeyPath
    $trustedExecutableSha256 = Get-MIR4Sha256File -Path (Assert-MIR4ExplicitExecutableV1 -Path $SshKeygenPath)
    if ([string]$attestation.payload.signing_provider.public_key -cne $trustedKey -or
        [string]$attestation.payload.signing_provider.public_key_fingerprint -cne $trustedFingerprint -or
        [string]$attestation.payload.signing_provider.executable_sha256 -cne $trustedExecutableSha256 -or
        [string]$attestation.payload.trusted_root.public_key_fingerprint -cne $trustedFingerprint -or
        $RevokedFingerprints -ccontains $trustedFingerprint -or
        @($attestation.payload.revocation_snapshot.revoked_fingerprints) -ccontains $trustedFingerprint) {
      return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSourceCommit) -and
        [string]$attestation.payload.source.commit -cne $ExpectedSourceCommit) {
      return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSourceTree) -and
        [string]$attestation.payload.source.tree -cne $ExpectedSourceTree) {
      return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedWorkflowRef) -and
        [string]$attestation.payload.workflow.ref -cne $ExpectedWorkflowRef) {
      return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedInventoryRecordSha256) -and
        [string]$attestation.payload.inventory.record_sha256 -cne $ExpectedInventoryRecordSha256.ToUpperInvariant()) {
      return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedProvenanceSha256) -and
        [string]$attestation.payload.provenance.sha256 -cne $ExpectedProvenanceSha256.ToUpperInvariant()) {
      return $false
    }
    if ([string]$attestation.payload.revocation_snapshot.source_commit -cne [string]$attestation.payload.source.commit -or
        [string]$attestation.signature.identity -cne [string]$attestation.payload.signing_provider.identity -or
        [string]$attestation.signature.namespace -cne [string]$attestation.payload.signing_provider.namespace) {
      return $false
    }
    $subjectNames = @($attestation.payload.subjects | ForEach-Object { [string]$_.name })
    if ($subjectNames.Count -ne 9 -or
        @($subjectNames | Sort-Object -Unique -CaseSensitive).Count -ne 9) {
      return $false
    }
    $targetNames = @($attestation.payload.targets | ForEach-Object { [string]$_.target })
    if ($targetNames.Count -ne 2 -or
        @($targetNames | Sort-Object -Unique -CaseSensitive).Count -ne 2 -or
        @($targetNames | Where-Object { $_ -cnotin @('f210', 'f200') }).Count -ne 0) {
      return $false
    }
    foreach ($target in $attestation.payload.targets) {
      $targetSubject = @($attestation.payload.subjects | Where-Object { [string]$_.name -ceq [string]$target.component_id })
      if ($targetSubject.Count -ne 1 -or
          [string]$target.sha256 -cne [string]$targetSubject[0].digest.sha256) {
        return $false
      }
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedTarget) -and
        @($attestation.payload.targets | Where-Object { [string]$_.target -ceq $ExpectedTarget }).Count -ne 1) {
      return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSubjectName)) {
      $matches = @($attestation.payload.subjects | Where-Object { [string]$_.name -ceq $ExpectedSubjectName })
      if ($matches.Count -ne 1 -or
          (-not [string]::IsNullOrWhiteSpace($ExpectedSubjectSha256) -and
           [string]$matches[0].digest.sha256 -cne $ExpectedSubjectSha256.ToLowerInvariant())) {
        return $false
      }
    }
    if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $attestation.payload.subjects) -cne
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $attestation.payload.github_subjects)) {
      return $false
    }
    $signatureBytes = [Convert]::FromBase64String([string]$attestation.signature.signature_base64)
    if ((Get-MIR4Sha256Bytes -Bytes $signatureBytes) -cne [string]$attestation.signature.signature_sha256 -or
        [string]$attestation.signature.payload_record_sha256 -cne [string]$attestation.payload.record_sha256) {
      return $false
    }
    if (-not (Test-Path -LiteralPath $scratch -PathType Container)) {
      New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    }
    $workRoot = Join-Path $scratch ('verify-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
    try {
      $payloadPath = Join-Path $workRoot 'payload.json'
      Write-MIR4SupplyChainRecord -Record $attestation.payload -Path $payloadPath
      $signaturePath = Join-Path $workRoot 'payload.json.sig'
      [IO.File]::WriteAllBytes($signaturePath, $signatureBytes)
      return Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $TrustedPublicKeyPath -Identity ([string]$attestation.signature.identity) -Namespace ([string]$attestation.signature.namespace) -PayloadPath $payloadPath -SignaturePath $signaturePath -ScratchRoot (Join-Path $workRoot 'allowed')
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
