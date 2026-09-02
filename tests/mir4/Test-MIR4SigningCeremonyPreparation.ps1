# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/SigningCeremonyPreparation.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')

function Assert-MIR4SigningPreparationTest {
  param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[$Code]" }
}
function Assert-MIR4SigningPreparationThrows {
  param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Code)
  $threw = $false
  try { & $Action } catch { $threw = $true }
  if (-not $threw) { throw "[$Code]" }
}

$sshCandidates = @(
  'C:\Windows\System32\OpenSSH\ssh-keygen.exe',
  'C:\Program Files\Git\usr\bin\ssh-keygen.exe'
)
$sshKeygen = @($sshCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
Assert-MIR4SigningPreparationTest ($sshKeygen.Count -eq 1) 'mir4-signing-preparation-ssh-keygen-unavailable'
$authority = Get-MIR4SigningCeremonyPreparationAuthorityV1 -RepoRoot $repo
Assert-MIR4SigningPreparationTest ([string]$authority.state -ceq 'MACHINE-PREPARATION-COMPLETE-HUMAN-CEREMONY-REQUIRED') 'mir4-signing-preparation-authority-state'

$externalBase = Join-Path ([IO.Path]::GetTempPath()) ('mir4-signing-root-contract-' + [guid]::NewGuid().ToString('N'))
$rootResult = Test-MIR4SigningRootSetV1 -RepoRoot $repo -SigningHome (Join-Path $externalBase 'signing') -RecoveryCopyAHome (Join-Path $externalBase 'recovery-a') -RecoveryCopyBHome (Join-Path $externalBase 'recovery-b') -PublisherHome (Join-Path $externalBase 'publisher') -BuilderRoots @((Join-Path $externalBase 'builder'))
Assert-MIR4SigningPreparationTest ([string]$rootResult.status -ceq 'passed') 'mir4-signing-preparation-root-positive'
Assert-MIR4SigningPreparationThrows {
  Test-MIR4SigningRootSetV1 -RepoRoot $repo -SigningHome (Join-Path $externalBase 'shared') -RecoveryCopyAHome (Join-Path $externalBase 'shared\a') -RecoveryCopyBHome (Join-Path $externalBase 'recovery-b') -PublisherHome (Join-Path $externalBase 'publisher')
} 'mir4-signing-preparation-root-overlap-negative'
Assert-MIR4SigningPreparationThrows {
  Test-MIR4SigningRootSetV1 -RepoRoot $repo -SigningHome (Join-Path $repo 'build\forbidden-signing') -RecoveryCopyAHome (Join-Path $externalBase 'recovery-a') -RecoveryCopyBHome (Join-Path $externalBase 'recovery-b') -PublisherHome (Join-Path $externalBase 'publisher')
} 'mir4-signing-preparation-repository-root-negative'

$approvedSid = 'S-1-5-21-1000-1000-1000-1001'
$aclRows = @([pscustomobject][ordered]@{sid=$approvedSid;type='Allow';rights='FullControl';is_inherited=$false})
Assert-MIR4SigningPreparationTest (Test-MIR4SigningAclPolicyV1 -InheritanceProtected $true -Rows $aclRows -AllowedSids @($approvedSid) -OwnerSid $approvedSid) 'mir4-signing-preparation-acl-positive'
$broadRows = @($aclRows + [pscustomobject][ordered]@{sid='S-1-1-0';type='Allow';rights='Read';is_inherited=$false})
Assert-MIR4SigningPreparationTest (-not (Test-MIR4SigningAclPolicyV1 -InheritanceProtected $true -Rows $broadRows -AllowedSids @($approvedSid) -OwnerSid $approvedSid)) 'mir4-signing-preparation-acl-broad-negative'
Assert-MIR4SigningPreparationTest (-not (Test-MIR4SigningAclPolicyV1 -InheritanceProtected $false -Rows $aclRows -AllowedSids @($approvedSid) -OwnerSid $approvedSid)) 'mir4-signing-preparation-acl-inheritance-negative'
Assert-MIR4SigningPreparationTest (-not (Test-MIR4SigningAclPolicyV1 -InheritanceProtected $true -Rows $aclRows -AllowedSids @($approvedSid) -OwnerSid 'S-1-5-21-1000-1000-1000-1002')) 'mir4-signing-preparation-acl-owner-negative'

$scratch = Join-Path $repo ('build\tests\mir4-signing-ceremony-preparation\' + [guid]::NewGuid().ToString('N'))
try {
  $receipt = New-MIR4SigningCeremonyPreparationReceiptV1 -RepoRoot $repo -SshKeygenPath $sshKeygen[0] -ScratchRoot $scratch
  Assert-MIR4SigningPreparationTest (Test-MIR4SigningCeremonyPreparationReceiptV1 -Receipt $receipt -RepoRoot $repo) 'mir4-signing-preparation-receipt'
  Assert-MIR4SigningPreparationTest ([string]$receipt.package_source_sha256 -ceq (Get-MIR4CurrentPackageSourceSha256 -RepoRoot $repo)) 'mir4-signing-preparation-package-non-interference'
  Assert-MIR4SigningPreparationTest (@($receipt.human_blockers).Count -eq 4) 'mir4-signing-preparation-human-blockers'
  Assert-MIR4SigningPreparationTest ([bool]$receipt.rehearsal.original_acl_policy_passed -and [bool]$receipt.rehearsal.restored_acl_policy_passed -and [bool]$receipt.rehearsal.restored_acl_matched) 'mir4-signing-preparation-acl-rehearsal'
  Assert-MIR4SigningPreparationTest (-not (Test-Path -LiteralPath $scratch -PathType Container) -or @(Get-ChildItem -LiteralPath $scratch -Force -ErrorAction SilentlyContinue).Count -eq 0) 'mir4-signing-preparation-secret-residue'
  $receiptText = ConvertTo-MIR4BootstrapCanonicalJson -Value $receipt
  Assert-MIR4SigningPreparationTest ($receiptText -notmatch [regex]::Escape($scratch)) 'mir4-signing-preparation-path-leak'
  Assert-MIR4SigningPreparationTest ($receiptText -notmatch '(?i)(BEGIN OPENSSH PRIVATE KEY|passphrase\s*[:=]|encryption[_ -]?key\s*[:=])') 'mir4-signing-preparation-secret-leak'
  $productionSchema = Join-Path $repo 'spec/schemas/mir4-protected-signing-ceremony-receipt-v1.schema.json'
  $templateText = [IO.File]::ReadAllText((Join-Path $repo 'spec/templates/mir4-protected-signing-ceremony-receipt-v1.template.json'))
  $templateValidAsEvidence = $true
  try { $templateValidAsEvidence = [bool]($templateText | Test-Json -SchemaFile $productionSchema -ErrorAction Stop) } catch { $templateValidAsEvidence = $false }
  Assert-MIR4SigningPreparationTest (-not $templateValidAsEvidence) 'mir4-signing-preparation-template-confusion'
  $libraryText = [IO.File]::ReadAllText((Join-Path $repo 'tools/lib/mir4/SigningCeremonyPreparation.ps1'))
  Assert-MIR4SigningPreparationTest ($libraryText -cnotmatch '(?m)["'']-N["'']') 'mir4-signing-preparation-command-line-passphrase'
  [pscustomobject][ordered]@{
    status = 'passed'
    authority_sha256 = [string]$receipt.authority.sha256
    receipt_sha256 = [string]$receipt.record_sha256
    ssh_keygen_sha256 = [string]$receipt.toolchain.ssh_keygen_sha256
    public_key_fingerprint = [string]$receipt.rehearsal.public_key_fingerprint
    recovery_copies = @($receipt.rehearsal.copies).Count
    restored_signature_verified = [bool]$receipt.rehearsal.restored_challenge_signature_verified
    restored_acl_matched = [bool]$receipt.rehearsal.restored_acl_matched
    ephemeral_plaintext_destroyed = [bool]$receipt.rehearsal.ephemeral_plaintext_destroyed
    human_blockers = @($receipt.human_blockers | ForEach-Object { [string]$_.id })
    package_source_sha256 = [string]$receipt.package_source_sha256
    production_authority = $false
    release_transition_performed = $false
  }
} finally {
  if (Test-Path -LiteralPath $scratch -PathType Container) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
