if (-not (Get-Command Get-MIR4BootstrapRecordSha256 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'BootstrapMaterialization.ps1')
}
if (-not (Get-Command Test-MIR4ReleaseGovernanceAuthority -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'ReleaseGovernance.ps1')
}
if (-not (Get-Command New-MIR4ProofOnlyEd25519KeyPairV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '../../mir/application/custody/OfflineCandidateCustody.ps1')
}
if (-not (Get-Command Get-MIRPackageSourceFingerprint -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '..\validation\PackageIdentity.ps1')
}

$script:MIR4SigningPreparationAuthorityPathV1 = '.mir/releases/governance/mir4/signing-ceremony-preparation.json'
$script:MIR4SigningPreparationAuthoritySchemaPathV1 = 'spec/schemas/mir4-signing-ceremony-preparation-authority-v1.schema.json'
$script:MIR4SigningPreparationReceiptSchemaPathV1 = 'spec/schemas/mir4-signing-ceremony-preparation-receipt-v1.schema.json'
$script:MIR4ProtectedSigningReceiptSchemaPathV1 = 'spec/schemas/mir4-protected-signing-ceremony-receipt-v1.schema.json'
$script:MIR4ProtectedSigningReceiptTemplatePathV1 = 'spec/templates/mir4-protected-signing-ceremony-receipt-v1.template.json'
$script:MIR4SigningRehearsalIdentityV1 = 'mir4-t15-signing-recovery-rehearsal'
$script:MIR4SigningRehearsalNamespaceV1 = 'mir4-ledger'
$script:MIR4SigningBroadPrincipalSidsV1 = @('S-1-1-0','S-1-5-11','S-1-5-32-545','S-1-5-32-546')

function Assert-MIR4SigningPreparationConditionV1 {
  param(
    [Parameter(Mandatory)][bool]$Condition,
    [Parameter(Mandatory)][string]$Code,
    [string]$Detail = ''
  )
  if (-not $Condition) { throw "[$Code] $Detail".TrimEnd() }
}

function Get-MIR4SigningCeremonyPreparationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo $script:MIR4SigningPreparationAuthorityPathV1
  $schema = Join-Path $repo $script:MIR4SigningPreparationAuthoritySchemaPathV1
  Assert-MIR4SigningPreparationConditionV1 (Test-Path -LiteralPath $path -PathType Leaf) 'mir4-signing-preparation-authority-missing'
  Assert-MIR4SigningPreparationConditionV1 (Test-Path -LiteralPath $schema -PathType Leaf) 'mir4-signing-preparation-authority-schema-missing'
  $text = [IO.File]::ReadAllText($path)
  Assert-MIR4SigningPreparationConditionV1 ($text | Test-Json -SchemaFile $schema -ErrorAction Stop) 'mir4-signing-preparation-authority-schema'
  $authority = $text | ConvertFrom-Json -Depth 50 -DateKind String

  $rootVariables = @($authority.logical_roots | ForEach-Object { [string]$_.environment_variable })
  $expectedVariables = @('MIR_SIGNING_HOME','MIR_RECOVERY_COPY_A_HOME','MIR_RECOVERY_COPY_B_HOME')
  Assert-MIR4SigningPreparationConditionV1 (
    (@($rootVariables | Sort-Object) -join '|') -ceq (@($expectedVariables | Sort-Object) -join '|')
  ) 'mir4-signing-preparation-logical-roots'
  Assert-MIR4SigningPreparationConditionV1 (@($authority.recovery.required_copies)[0] -eq 2) 'mir4-signing-preparation-recovery-count'
  Assert-MIR4SigningPreparationConditionV1 (-not [bool]$authority.production_signing_authorized) 'mir4-signing-preparation-production-authority'
  Assert-MIR4SigningPreparationConditionV1 (-not [bool]$authority.secret_values_present) 'mir4-signing-preparation-secret-marker'
  Assert-MIR4SigningPreparationConditionV1 (@($authority.acl_policy.maintainer_approved_sids).Count -eq 0) 'mir4-signing-preparation-invented-sids'
  foreach ($property in $authority.prohibited_transitions.PSObject.Properties) {
    Assert-MIR4SigningPreparationConditionV1 ([bool]$property.Value) 'mir4-signing-preparation-transition-open' ([string]$property.Name)
  }

  $release = Test-MIR4ReleaseGovernanceAuthority -RepoRoot $repo
  Assert-MIR4SigningPreparationConditionV1 ([string]$release.state -ceq 'BLOCKED-HUMAN-SECRET-INPUT') 'mir4-signing-preparation-release-state'
  Assert-MIR4SigningPreparationConditionV1 ($null -eq $release.signing_authority.public_key -and $null -eq $release.signing_authority.fingerprint) 'mir4-signing-preparation-production-key-present'
  $signers = [IO.File]::ReadAllText((Join-Path $repo '.mir/releases/governance/mir4/allowed-signers.json')) | ConvertFrom-Json -Depth 20 -DateKind String
  Assert-MIR4SigningPreparationConditionV1 (@($signers.rows).Count -eq 0) 'mir4-signing-preparation-signer-row-present'

  $templatePath = Join-Path $repo ([string]$authority.tracked_outputs.production_receipt_template)
  $productionSchema = Join-Path $repo ([string]$authority.tracked_outputs.production_receipt_schema)
  foreach ($required in @($templatePath, $productionSchema, (Join-Path $repo ([string]$authority.tracked_outputs.preparation_receipt_schema)))) {
    Assert-MIR4SigningPreparationConditionV1 (Test-Path -LiteralPath $required -PathType Leaf) 'mir4-signing-preparation-output-missing' $required
  }
  $template = [IO.File]::ReadAllText($templatePath) | ConvertFrom-Json -Depth 30 -DateKind String
  Assert-MIR4SigningPreparationConditionV1 ([string]$template.kind -ceq 'MIR4ProtectedSigningCeremonyReceiptTemplateV1') 'mir4-signing-preparation-template-kind'
  Assert-MIR4SigningPreparationConditionV1 ([string]$template.status -ceq 'TEMPLATE-NOT-EVIDENCE' -and $null -eq $template.record_sha256) 'mir4-signing-preparation-template-evidence'
  $templateValidAsEvidence = $true
  try {
    $templateValidAsEvidence = [bool](([IO.File]::ReadAllText($templatePath)) | Test-Json -SchemaFile $productionSchema -ErrorAction Stop)
  } catch {
    $templateValidAsEvidence = $false
  }
  Assert-MIR4SigningPreparationConditionV1 (-not $templateValidAsEvidence) 'mir4-signing-preparation-template-valid-as-evidence'
  return $authority
}

function Test-MIR4SigningPathOverlapV1 {
  param([Parameter(Mandatory)][string]$Left, [Parameter(Mandatory)][string]$Right)

  $leftPath = [IO.Path]::GetFullPath($Left).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $rightPath = [IO.Path]::GetFullPath($Right).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  return $leftPath.Equals($rightPath, [StringComparison]::OrdinalIgnoreCase) -or
    $leftPath.StartsWith($rightPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
    $rightPath.StartsWith($leftPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Test-MIR4SigningRootSetV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SigningHome,
    [Parameter(Mandatory)][string]$RecoveryCopyAHome,
    [Parameter(Mandatory)][string]$RecoveryCopyBHome,
    [Parameter(Mandatory)][string]$PublisherHome,
    [string[]]$BuilderRoots = @()
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $inputRows = [ordered]@{
    signing = $SigningHome
    recovery_a = $RecoveryCopyAHome
    recovery_b = $RecoveryCopyBHome
    publisher = $PublisherHome
  }
  $resolved = [ordered]@{}
  foreach ($entry in $inputRows.GetEnumerator()) {
    Assert-MIR4SigningPreparationConditionV1 (-not [string]::IsNullOrWhiteSpace([string]$entry.Value) -and [IO.Path]::IsPathRooted([string]$entry.Value)) 'mir4-signing-root-absolute' ([string]$entry.Key)
    $resolved[$entry.Key] = [IO.Path]::GetFullPath([string]$entry.Value).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  }
  foreach ($role in @('signing','recovery_a','recovery_b')) {
    Assert-MIR4SigningPreparationConditionV1 (-not (Test-MIR4SigningPathOverlapV1 -Left $repo -Right $resolved[$role])) 'mir4-signing-root-repository-overlap' $role
    Assert-MIR4SigningPreparationConditionV1 (-not (Test-MIR4SigningPathOverlapV1 -Left $resolved.publisher -Right $resolved[$role])) 'mir4-signing-root-publisher-overlap' $role
    foreach ($builder in $BuilderRoots) {
      Assert-MIR4SigningPreparationConditionV1 ([IO.Path]::IsPathRooted($builder)) 'mir4-signing-builder-root-absolute'
      Assert-MIR4SigningPreparationConditionV1 (-not (Test-MIR4SigningPathOverlapV1 -Left $builder -Right $resolved[$role])) 'mir4-signing-root-builder-overlap' $role
    }
  }
  foreach ($pair in @(@('signing','recovery_a'),@('signing','recovery_b'),@('recovery_a','recovery_b'))) {
    Assert-MIR4SigningPreparationConditionV1 (-not (Test-MIR4SigningPathOverlapV1 -Left $resolved[$pair[0]] -Right $resolved[$pair[1]])) 'mir4-signing-root-control-overlap' ($pair -join ':')
  }
  return [pscustomobject][ordered]@{
    status = 'passed'
    roles = @('signing','recovery_a','recovery_b')
    absolute_external = $true
    pairwise_disjoint = $true
    publisher_separated = $true
    builder_roots_checked = @($BuilderRoots).Count
  }
}

function Test-MIR4SigningAclPolicyV1 {
  param(
    [Parameter(Mandatory)][bool]$InheritanceProtected,
    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AllowedSids,
    [Parameter(Mandatory)][string]$OwnerSid
  )

  try {
    if (-not $InheritanceProtected -or $AllowedSids.Count -eq 0 -or @($AllowedSids | Sort-Object -Unique).Count -ne $AllowedSids.Count -or @($AllowedSids | Where-Object { $_ -notmatch '^S-1-' }).Count -ne 0) { return $false }
    if (@($AllowedSids | Where-Object { $_ -in $script:MIR4SigningBroadPrincipalSidsV1 }).Count -ne 0) { return $false }
    if ($OwnerSid -notmatch '^S-1-' -or $OwnerSid -notin $AllowedSids -or $OwnerSid -in $script:MIR4SigningBroadPrincipalSidsV1) { return $false }
    foreach ($row in $Rows) {
      $sid = [string]$row.sid
      $type = [string]$row.type
      $rights = [string]$row.rights
      if ([bool]$row.is_inherited) { return $false }
      if ($type -ceq 'Allow' -and ($sid -in $script:MIR4SigningBroadPrincipalSidsV1 -or $sid -notin $AllowedSids)) { return $false }
      if ($type -notin @('Allow','Deny') -or [string]::IsNullOrWhiteSpace($rights)) { return $false }
    }
    foreach ($sid in $AllowedSids) {
      $full = @($Rows | Where-Object {
        [string]$_.sid -ceq $sid -and [string]$_.type -ceq 'Allow' -and [string]$_.rights -match '(^|,\s*)(FullControl|Modify)($|,)'
      })
      if ($full.Count -eq 0) { return $false }
    }
    return $true
  } catch { return $false }
}

function Get-MIR4SigningAclAssessmentV1 {
  param([Parameter(Mandatory)][string]$Path)

  Assert-MIR4SigningPreparationConditionV1 ([IO.Path]::IsPathRooted($Path) -and (Test-Path -LiteralPath $Path)) 'mir4-signing-acl-path'
  $acl = Get-Acl -LiteralPath $Path
  $ownerSid = ([Security.Principal.NTAccount]$acl.Owner).Translate([Security.Principal.SecurityIdentifier]).Value
  $rows = @(
    foreach ($rule in $acl.Access) {
      $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
      [pscustomobject][ordered]@{
        sid = [string]$sid
        type = [string]$rule.AccessControlType
        rights = [string]$rule.FileSystemRights
        is_inherited = [bool]$rule.IsInherited
      }
    }
  ) | Sort-Object sid,type,rights,is_inherited
  return [pscustomobject][ordered]@{
    inheritance_protected = [bool]$acl.AreAccessRulesProtected
    owner_sid = [string]$ownerSid
    rows = @($rows)
  }
}

function Test-MIR4SigningPathAclV1 {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AllowedSids
  )

  try {
    $assessment = Get-MIR4SigningAclAssessmentV1 -Path $Path
    return Test-MIR4SigningAclPolicyV1 -InheritanceProtected ([bool]$assessment.inheritance_protected) -Rows @($assessment.rows) -AllowedSids $AllowedSids -OwnerSid ([string]$assessment.owner_sid)
  } catch { return $false }
}

function New-MIR4SigningAesGcmEnvelopeV1 {
  param(
    [Parameter(Mandatory)][byte[]]$Plaintext,
    [Parameter(Mandatory)][byte[]]$Key,
    [Parameter(Mandatory)][string]$CopyId
  )

  Assert-MIR4SigningPreparationConditionV1 ($Key.Length -eq 32) 'mir4-signing-rehearsal-key-length'
  $nonce = [byte[]]::new(12)
  [Security.Cryptography.RandomNumberGenerator]::Fill($nonce)
  $tag = [byte[]]::new(16)
  $ciphertext = [byte[]]::new($Plaintext.Length)
  $associated = [Text.UTF8Encoding]::new($false).GetBytes("MIR4-SIGNING-RECOVERY-REHEARSAL-V1|$CopyId")
  $aes = [Security.Cryptography.AesGcm]::new($Key, 16)
  try {
    $aes.Encrypt($nonce, $Plaintext, $ciphertext, $tag, $associated)
    return [pscustomobject][ordered]@{
      schema = 1
      kind = 'MIR4SigningRecoveryRehearsalEnvelopeV1'
      scope = 'local-non-production-proof-only'
      copy_id = $CopyId
      algorithm = 'AES-256-GCM-IN-MEMORY-NON-PRODUCTION'
      associated_data = [Convert]::ToBase64String($associated)
      nonce = [Convert]::ToBase64String($nonce)
      tag = [Convert]::ToBase64String($tag)
      ciphertext = [Convert]::ToBase64String($ciphertext)
      production_authority = $false
    }
  } finally {
    $aes.Dispose()
    [Array]::Clear($nonce, 0, $nonce.Length)
    [Array]::Clear($tag, 0, $tag.Length)
    [Array]::Clear($ciphertext, 0, $ciphertext.Length)
    [Array]::Clear($associated, 0, $associated.Length)
  }
}

function Unprotect-MIR4SigningAesGcmEnvelopeV1 {
  param(
    [Parameter(Mandatory)]$Envelope,
    [Parameter(Mandatory)][byte[]]$Key
  )

  Assert-MIR4SigningPreparationConditionV1 ([string]$Envelope.kind -ceq 'MIR4SigningRecoveryRehearsalEnvelopeV1' -and -not [bool]$Envelope.production_authority) 'mir4-signing-rehearsal-envelope'
  $nonce = [Convert]::FromBase64String([string]$Envelope.nonce)
  $tag = [Convert]::FromBase64String([string]$Envelope.tag)
  $ciphertext = [Convert]::FromBase64String([string]$Envelope.ciphertext)
  $associated = [Convert]::FromBase64String([string]$Envelope.associated_data)
  $plaintext = [byte[]]::new($ciphertext.Length)
  $aes = [Security.Cryptography.AesGcm]::new($Key, 16)
  try {
    $aes.Decrypt($nonce, $ciphertext, $tag, $plaintext, $associated)
    return $plaintext
  } catch {
    [Array]::Clear($plaintext, 0, $plaintext.Length)
    throw
  } finally {
    $aes.Dispose()
    [Array]::Clear($nonce, 0, $nonce.Length)
    [Array]::Clear($tag, 0, $tag.Length)
    [Array]::Clear($ciphertext, 0, $ciphertext.Length)
    [Array]::Clear($associated, 0, $associated.Length)
  }
}

function Invoke-MIR4SigningRecoveryRehearsalV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [Parameter(Mandatory)][string]$SourceCommit,
    [Parameter(Mandatory)][string]$SourceTree
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $scratch = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $ScratchRoot -Label 'Signing ceremony rehearsal scratch root'
  if (-not (Test-Path -LiteralPath $scratch -PathType Container)) { New-Item -ItemType Directory -Force -Path $scratch | Out-Null }
  $workRoot = Join-Path $scratch ('signing-recovery-' + [guid]::NewGuid().ToString('N'))
  $null = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $workRoot -Label 'Signing ceremony rehearsal work root'
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

  [byte[]]$privateBytes = $null
  [byte[]]$keyA = $null
  [byte[]]$keyB = $null
  [byte[]]$decryptedA = $null
  [byte[]]$decryptedB = $null
  $result = $null
  try {
    $signingRoot = Join-Path $workRoot 'signing'
    $recoveryARoot = Join-Path $workRoot 'recovery-a'
    $recoveryBRoot = Join-Path $workRoot 'recovery-b'
    $restoreRoot = Join-Path $workRoot 'clean-restore'
    foreach ($path in @($signingRoot,$recoveryARoot,$recoveryBRoot,$restoreRoot)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
    $privatePath = Join-Path $signingRoot 'mir4-rehearsal-ed25519'
    $publicPath = $privatePath + '.pub'
    $provider = New-MIR4ProofOnlyEd25519KeyPairV1 -RepoRoot $repo -SshKeygenPath $SshKeygenPath -PrivateKeyPath $privatePath -PublicKeyPath $publicPath -Identity $script:MIR4SigningRehearsalIdentityV1
    $publicKey = Get-MIR4OpenSshPublicKeyLineV1 -PublicKeyPath $publicPath
    $privateAcl = Get-Acl -LiteralPath $privatePath
    $originalAclAssessment = Get-MIR4SigningAclAssessmentV1 -Path $privatePath
    $proofAllowedSids = @($originalAclAssessment.rows | Where-Object type -ceq 'Allow' | ForEach-Object { [string]$_.sid } | Sort-Object -Unique)
    Assert-MIR4SigningPreparationConditionV1 (Test-MIR4SigningAclPolicyV1 -InheritanceProtected ([bool]$originalAclAssessment.inheritance_protected) -Rows @($originalAclAssessment.rows) -AllowedSids $proofAllowedSids -OwnerSid ([string]$originalAclAssessment.owner_sid)) 'mir4-signing-rehearsal-original-acl'
    $privateBytes = [IO.File]::ReadAllBytes($privatePath)
    $privateSha = Get-MIR4Sha256Bytes -Bytes $privateBytes

    $challengePath = Join-Path $workRoot 'challenge.txt'
    $challenge = "MIR4 T15 NON-PRODUCTION SIGNING AND RECOVERY REHEARSAL`ncommit=$SourceCommit`ntree=$SourceTree`nnamespace=$($script:MIR4SigningRehearsalNamespaceV1)`nproduction_authority=false`n"
    [IO.File]::WriteAllText($challengePath, $challenge, [Text.UTF8Encoding]::new($false))

    $keyA = [byte[]]::new(32)
    $keyB = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($keyA)
    [Security.Cryptography.RandomNumberGenerator]::Fill($keyB)
    $envelopeA = New-MIR4SigningAesGcmEnvelopeV1 -Plaintext $privateBytes -Key $keyA -CopyId 'rehearsal-copy-a'
    $envelopeB = New-MIR4SigningAesGcmEnvelopeV1 -Plaintext $privateBytes -Key $keyB -CopyId 'rehearsal-copy-b'
    $copyAPath = Join-Path $recoveryARoot 'copy-a.json'
    $copyBPath = Join-Path $recoveryBRoot 'copy-b.json'
    [IO.File]::WriteAllText($copyAPath, (ConvertTo-MIR4BootstrapCanonicalJson -Value $envelopeA) + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($copyBPath, (ConvertTo-MIR4BootstrapCanonicalJson -Value $envelopeB) + "`n", [Text.UTF8Encoding]::new($false))
    $copyASha = Get-MIR4Sha256File -Path $copyAPath
    $copyBSha = Get-MIR4Sha256File -Path $copyBPath
    Assert-MIR4SigningPreparationConditionV1 ($copyASha -cne $copyBSha) 'mir4-signing-rehearsal-copy-collision'

    $decryptedA = Unprotect-MIR4SigningAesGcmEnvelopeV1 -Envelope $envelopeA -Key $keyA
    $decryptedB = Unprotect-MIR4SigningAesGcmEnvelopeV1 -Envelope $envelopeB -Key $keyB
    Assert-MIR4SigningPreparationConditionV1 ((Get-MIR4Sha256Bytes -Bytes $decryptedA) -ceq $privateSha) 'mir4-signing-rehearsal-copy-a-decrypt'
    Assert-MIR4SigningPreparationConditionV1 ((Get-MIR4Sha256Bytes -Bytes $decryptedB) -ceq $privateSha) 'mir4-signing-rehearsal-copy-b-decrypt'

    [IO.File]::Delete($privatePath)
    Assert-MIR4SigningPreparationConditionV1 (-not (Test-Path -LiteralPath $privatePath)) 'mir4-signing-rehearsal-original-private-retained'
    $restoredPath = Join-Path $restoreRoot 'mir4-rehearsal-ed25519'
    [IO.File]::WriteAllBytes($restoredPath, $decryptedA)
    Set-Acl -LiteralPath $restoredPath -AclObject $privateAcl
    $restoredAclAssessment = Get-MIR4SigningAclAssessmentV1 -Path $restoredPath
    Assert-MIR4SigningPreparationConditionV1 (Test-MIR4SigningAclPolicyV1 -InheritanceProtected ([bool]$restoredAclAssessment.inheritance_protected) -Rows @($restoredAclAssessment.rows) -AllowedSids $proofAllowedSids -OwnerSid ([string]$restoredAclAssessment.owner_sid)) 'mir4-signing-rehearsal-restored-acl'
    Assert-MIR4SigningPreparationConditionV1 ((ConvertTo-MIR4BootstrapCanonicalJson -Value $originalAclAssessment) -ceq (ConvertTo-MIR4BootstrapCanonicalJson -Value $restoredAclAssessment)) 'mir4-signing-rehearsal-acl-parity'
    $restoredPublicPath = $restoredPath + '.pub'
    $publicResult = Invoke-MIR4OpenSshProcessV1 -SshKeygenPath $SshKeygenPath -Arguments @('-y','-f',$restoredPath)
    Assert-MIR4SigningPreparationConditionV1 ($publicResult.exit_code -eq 0 -and $publicResult.stdout -match '^ssh-ed25519 ') 'mir4-signing-rehearsal-restored-public' ([string]$publicResult.stderr).Trim()
    [IO.File]::WriteAllText($restoredPublicPath, $publicResult.stdout.Trim() + "`n", [Text.UTF8Encoding]::new($false))
    $restoredFingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $restoredPublicPath
    Assert-MIR4SigningPreparationConditionV1 ($restoredFingerprint -ceq [string]$provider.public_key_fingerprint) 'mir4-signing-rehearsal-restored-fingerprint'

    $signaturePath = $challengePath + '.sig'
    $signResult = Invoke-MIR4OpenSshProcessV1 -SshKeygenPath $SshKeygenPath -Arguments @('-Y','sign','-f',$restoredPath,'-n',$script:MIR4SigningRehearsalNamespaceV1,$challengePath)
    Assert-MIR4SigningPreparationConditionV1 ($signResult.exit_code -eq 0 -and (Test-Path -LiteralPath $signaturePath -PathType Leaf)) 'mir4-signing-rehearsal-sign'
    $verified = Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicPath -Identity $script:MIR4SigningRehearsalIdentityV1 -Namespace $script:MIR4SigningRehearsalNamespaceV1 -PayloadPath $challengePath -SignaturePath $signaturePath -ScratchRoot (Join-Path $workRoot 'verify')
    Assert-MIR4SigningPreparationConditionV1 $verified 'mir4-signing-rehearsal-verify'

    [IO.File]::Delete($restoredPath)
    Assert-MIR4SigningPreparationConditionV1 (-not (Test-Path -LiteralPath $restoredPath)) 'mir4-signing-rehearsal-restored-private-retained'
    $result = [pscustomobject][ordered]@{
      scope = 'local-non-production-proof-only'
      production_authority = $false
      identity = $script:MIR4SigningRehearsalIdentityV1
      namespace = $script:MIR4SigningRehearsalNamespaceV1
      public_key_fingerprint = [string]$provider.public_key_fingerprint
      public_key_sha256 = Get-MIR4Sha256String -Value $publicKey
      challenge_sha256 = Get-MIR4Sha256File -Path $challengePath
      copies = @(
        [pscustomobject][ordered]@{copy_id='rehearsal-copy-a';encryption='AES-256-GCM-IN-MEMORY-NON-PRODUCTION';ciphertext_sha256=$copyASha;bytes=[long](Get-Item -LiteralPath $copyAPath).Length;separate_control_fixture=$true;decryption_verified=$true},
        [pscustomobject][ordered]@{copy_id='rehearsal-copy-b';encryption='AES-256-GCM-IN-MEMORY-NON-PRODUCTION';ciphertext_sha256=$copyBSha;bytes=[long](Get-Item -LiteralPath $copyBPath).Length;separate_control_fixture=$true;decryption_verified=$true}
      )
      copy_ciphertexts_distinct = $true
      both_copies_decrypted = $true
      original_plaintext_deleted_before_restore = $true
      original_acl_policy_passed = $true
      restored_acl_policy_passed = $true
      restored_acl_matched = $true
      restored_fingerprint_matched = $true
      restored_challenge_signature_verified = $true
      ephemeral_plaintext_destroyed = $false
      encryption_keys_retained = $false
      recovery_artifacts_retained = $false
    }
  } finally {
    foreach ($bytes in @($privateBytes,$keyA,$keyB,$decryptedA,$decryptedB)) {
      if ($null -ne $bytes) { [Array]::Clear($bytes, 0, $bytes.Length) }
    }
    if (Test-MIR4CustodyDescendantPathV1 -Root $scratch -Path $workRoot) {
      if (Test-Path -LiteralPath $workRoot -PathType Container) { Remove-Item -LiteralPath $workRoot -Recurse -Force }
    }
  }
  Assert-MIR4SigningPreparationConditionV1 (-not (Test-Path -LiteralPath $workRoot)) 'mir4-signing-rehearsal-cleanup'
  Assert-MIR4SigningPreparationConditionV1 ($null -ne $result) 'mir4-signing-rehearsal-no-result'
  $result.ephemeral_plaintext_destroyed = $true
  return $result
}

function New-MIR4SigningCeremonyPreparationReceiptV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [switch]$RequireClean
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authority = Get-MIR4SigningCeremonyPreparationAuthorityV1 -RepoRoot $repo
  $sshKeygen = Assert-MIR4ExplicitExecutableV1 -Path $SshKeygenPath
  $head = (& git -C $repo rev-parse HEAD).Trim()
  $tree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  $clean = @(& git -C $repo status --porcelain --untracked-files=normal).Count -eq 0
  if ($RequireClean) { Assert-MIR4SigningPreparationConditionV1 $clean 'mir4-signing-preparation-clean-tree' }

  $systemSid = 'S-1-5-18'
  $positiveRows = @([pscustomobject][ordered]@{sid=$systemSid;type='Allow';rights='FullControl';is_inherited=$false})
  Assert-MIR4SigningPreparationConditionV1 (Test-MIR4SigningAclPolicyV1 -InheritanceProtected $true -Rows $positiveRows -AllowedSids @($systemSid) -OwnerSid $systemSid) 'mir4-signing-preparation-acl-positive'
  $negativeRows = @($positiveRows + [pscustomobject][ordered]@{sid='S-1-1-0';type='Allow';rights='Read';is_inherited=$false})
  Assert-MIR4SigningPreparationConditionV1 (-not (Test-MIR4SigningAclPolicyV1 -InheritanceProtected $true -Rows $negativeRows -AllowedSids @($systemSid) -OwnerSid $systemSid)) 'mir4-signing-preparation-acl-negative'
  Assert-MIR4SigningPreparationConditionV1 (-not (Test-MIR4SigningAclPolicyV1 -InheritanceProtected $true -Rows $positiveRows -AllowedSids @($systemSid) -OwnerSid 'S-1-5-19')) 'mir4-signing-preparation-acl-owner-negative'

  $rehearsal = Invoke-MIR4SigningRecoveryRehearsalV1 -RepoRoot $repo -SshKeygenPath $sshKeygen -ScratchRoot $ScratchRoot -SourceCommit $head -SourceTree $tree
  $authorityPath = Join-Path $repo $script:MIR4SigningPreparationAuthorityPathV1
  $productionSchemaPath = Join-Path $repo $script:MIR4ProtectedSigningReceiptSchemaPathV1
  $templatePath = Join-Path $repo $script:MIR4ProtectedSigningReceiptTemplatePathV1
  $humanBlockers = @(
    [pscustomobject][ordered]@{id='protected-root-and-custodian-approval';state='requires-maintainer';next_action='Approve absolute MIR_SIGNING_HOME, MIR_RECOVERY_COPY_A_HOME, MIR_RECOVERY_COPY_B_HOME values and explicit custodian SIDs.'},
    [pscustomobject][ordered]@{id='protected-secret-authority';state='requires-maintainer';next_action='Supply the passphrase or encryption authority through an approved secret channel; never a command line or tracked record.'},
    [pscustomobject][ordered]@{id='interactive-key-ceremony';state='requires-maintainer';next_action='Follow docs/maintainer/mir4-release-governance.md#protected-signing-ceremony in a protected interactive console.'},
    [pscustomobject][ordered]@{id='ceremony-acceptance';state='requires-maintainer';next_action='Return an ACCEPTED receipt conforming to spec/schemas/mir4-protected-signing-ceremony-receipt-v1.schema.json.'}
  )
  $receipt = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4SigningCeremonyPreparationReceiptV1'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    programme_id = 'M4C02-09-24H'
    turn = 'T15'
    status = 'machine-preparation-passed-human-ceremony-required'
    source = [pscustomobject][ordered]@{repository='Julesc013/more-infinite-research';commit=$head;tree=$tree;working_tree_clean=$clean}
    authority = [pscustomobject][ordered]@{
      path = $script:MIR4SigningPreparationAuthorityPathV1
      sha256 = Get-MIR4Sha256File -Path $authorityPath
      production_receipt_schema_path = $script:MIR4ProtectedSigningReceiptSchemaPathV1
      production_receipt_schema_sha256 = Get-MIR4Sha256File -Path $productionSchemaPath
      template_path = $script:MIR4ProtectedSigningReceiptTemplatePathV1
      template_sha256 = Get-MIR4Sha256File -Path $templatePath
    }
    toolchain = [pscustomobject][ordered]@{ssh_keygen_sha256=(Get-MIR4Sha256File -Path $sshKeygen);algorithm='ssh-ed25519';signature_format='sshsig';rehearsal_encryption='AES-256-GCM-IN-MEMORY-NON-PRODUCTION'}
    logical_roots = [pscustomobject][ordered]@{
      environment_variables = @($authority.logical_roots | ForEach-Object { [string]$_.environment_variable })
      absolute_external_required = $true
      pairwise_disjoint_required = $true
      publisher_separation_required = $true
      configured_values_recorded = $false
    }
    acl_policy = [pscustomobject][ordered]@{
      inheritance_protected_required = $true
      explicit_approved_sids_required = $true
      approved_owner_required = $true
      broad_principals_forbidden = @($authority.acl_policy.broad_principals_forbidden)
      synthetic_positive_case = 'passed'
      synthetic_broad_principal_rejection = 'passed'
      synthetic_unapproved_owner_rejection = 'passed'
    }
    rehearsal = $rehearsal
    human_blockers = $humanBlockers
    package_source_sha256 = Get-MIRPackageSourceFingerprint -RepoRoot $repo
    production_transition_authority = [pscustomobject][ordered]@{source_freeze=$false;candidate_allocation=$false;production_signature=$false;seal=$false;promotion=$false;tag=$false;publication=$false}
    secret_values_present = $false
    record_sha256 = $null
  }
  $receipt.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $receipt
  return $receipt
}

function Test-MIR4SigningCeremonyPreparationReceiptV1 {
  param([Parameter(Mandatory)]$Receipt, [Parameter(Mandatory)][string]$RepoRoot)

  try {
    $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
    $schema = Join-Path $repo $script:MIR4SigningPreparationReceiptSchemaPathV1
    $json = ConvertTo-MIR4BootstrapCanonicalJson -Value $Receipt
    if (-not ($json | Test-Json -SchemaFile $schema -ErrorAction Stop)) { return $false }
    if ([string]$Receipt.record_sha256 -cne (Get-MIR4BootstrapRecordSha256 -Record $Receipt)) { return $false }
    if ([string]$Receipt.source.commit -cne (& git -C $repo rev-parse HEAD).Trim() -or [string]$Receipt.source.tree -cne (& git -C $repo rev-parse 'HEAD^{tree}').Trim()) { return $false }
    if ([string]$Receipt.authority.sha256 -cne (Get-MIR4Sha256File -Path (Join-Path $repo $script:MIR4SigningPreparationAuthorityPathV1))) { return $false }
    if (@($Receipt.rehearsal.copies).Count -ne 2 -or [string]$Receipt.rehearsal.copies[0].ciphertext_sha256 -ceq [string]$Receipt.rehearsal.copies[1].ciphertext_sha256) { return $false }
    if (@($Receipt.production_transition_authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0 -or [bool]$Receipt.secret_values_present) { return $false }
    return $true
  } catch { return $false }
}
