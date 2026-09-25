Set-StrictMode -Version Latest

$mir42SealRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Get-MIR4CanonicalPackageSourceFingerprint -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/mir/application/package/PackageAuthority.ps1')
}

$script:MIR42SealTargets = @('f210', 'f200', 'f110', 'f100')

function Read-MIR42SealRecord {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "[$Code-missing] $Path" }
  try { $record = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100 -DateKind String }
  catch { throw "[$Code-json] $Path" }
  if ($null -eq $record) { throw "[$Code-empty] $Path" }
  if ($record.PSObject.Properties.Name -contains 'record_sha256') {
    if (-not (Test-MIR4BootstrapRecordHash -Record $record)) { throw "[$Code-record-hash] $Path" }
  }
  return [pscustomobject][ordered]@{
    path = (Resolve-Path -LiteralPath $Path).Path
    sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    record = $record
  }
}

function Assert-MIR42SealSource {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Source,[Parameter(Mandatory)][string]$Code)
  foreach ($field in @('commit','tree','package_source_sha256')) {
    if ($Source.PSObject.Properties.Name -notcontains $field -or [string]::IsNullOrWhiteSpace([string]$Source.$field)) {
      throw "[$Code-source-field] $field"
    }
  }
  $commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
  $tree = (& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
  if ($LASTEXITCODE -ne 0 -or $commit -cne [string]$Source.commit -or $tree -cne [string]$Source.tree) {
    throw "[$Code-source-tree-drift]"
  }
  $packageSource = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot
  if ($packageSource -cne [string]$Source.package_source_sha256) { throw "[$Code-package-source-drift]" }
  return [pscustomobject][ordered]@{commit=$commit;tree=$tree;package_source_sha256=$packageSource}
}

function Assert-MIR42SealTargetSet {
  param([Parameter(Mandatory)]$Rows,[Parameter(Mandatory)][string]$Code)
  $actual = @($Rows | ForEach-Object { [string]$_.target })
  if ($actual.Count -ne 4 -or ($actual -join '|') -cne ($script:MIR42SealTargets -join '|')) {
    throw "[$Code-target-set]"
  }
}

function Get-MIR42ExactFourTargetCandidate {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$CandidateManifestPath)
  $candidateInput = Read-MIR42SealRecord -Path $CandidateManifestPath -Code 'mir42-seal-candidate'
  $candidate = $candidateInput.record
  if ([string]$candidate.kind -cne 'MIR42FourTargetCandidateManifestV1' -or
      [string]$candidate.status -cne 'private-deterministic-four-target-candidate-built-unqualified' -or
      -not [bool]$candidate.build_complete -or
      [string]$candidate.qualification -cne 'not-performed' -or
      [bool]$candidate.publication_authorized) {
    throw '[mir42-seal-candidate-state]'
  }
  $candidateSource = [pscustomobject][ordered]@{
    commit = [string]$candidate.source.commit
    tree = [string]$candidate.source.tree
    package_source_sha256 = [string]$candidate.package_source_sha256
  }
  $source = Assert-MIR42SealSource -RepoRoot $RepoRoot -Source $candidateSource -Code 'mir42-seal-candidate'
  Assert-MIR42SealTargetSet -Rows @($candidate.targets) -Code 'mir42-seal-candidate'
  $root = Split-Path -Parent $candidateInput.path
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($target in @($candidate.targets)) {
    foreach ($field in @('target','distribution_version','target_row_path','asset','content_sha256','entry_count')) {
      if ($target.PSObject.Properties.Name -notcontains $field) { throw "[mir42-seal-candidate-target-field] $([string]$target.target)/$field" }
    }
    if (-not [bool]$target.asset.bytes -or [string]$target.asset.sha256 -notmatch '^[A-F0-9]{64}$') {
      throw "[mir42-seal-candidate-asset-shape] $([string]$target.target)"
    }
    $assetPath = Join-Path $root ([string]$target.asset.path)
    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$target.asset.sha256 -or
        [int64](Get-Item -LiteralPath $assetPath).Length -ne [int64]$target.asset.bytes) {
      throw "[mir42-seal-candidate-asset-drift] $([string]$target.target)"
    }
    $rowPath = Join-Path $root ([string]$target.target_row_path)
    $rowInput = Read-MIR42SealRecord -Path $rowPath -Code 'mir42-seal-target-row'
    $row = $rowInput.record
    if ([string]$row.target -cne [string]$target.target -or
        [string]$row.distribution_version -cne [string]$target.distribution_version -or
        [string]$row.asset.sha256 -cne [string]$target.asset.sha256 -or
        [string]$row.content_sha256 -cne [string]$target.content_sha256 -or
        [int]$row.entry_count -ne [int]$target.entry_count -or
        -not [bool]$row.deterministic_archive_bytes -or -not [bool]$row.package_excluded_surface -or
        [string]$row.build_a_sha256 -cne [string]$target.asset.sha256 -or
        [string]$row.build_b_sha256 -cne [string]$target.asset.sha256) {
      throw "[mir42-seal-candidate-target-row-drift] $([string]$target.target)"
    }
    $rows.Add([pscustomobject][ordered]@{
      target = [string]$target.target
      distribution_version = [string]$target.distribution_version
      archive_sha256 = [string]$target.asset.sha256
      content_sha256 = [string]$target.content_sha256
      entry_count = [int]$target.entry_count
    })
  }
  return [pscustomobject][ordered]@{identity=$candidateInput;source=$source;targets=@($rows)}
}

function Assert-MIR42ReceiptBinding {
  param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][string]$Code)
  $record = $Receipt.record
  if ([string]$record.candidate_manifest.sha256 -cne [string]$Candidate.identity.sha256 -or
      [string]$record.candidate_manifest.record_sha256 -cne [string]$Candidate.identity.record.record_sha256 -or
      [string]$record.source.commit -cne [string]$Candidate.source.commit -or
      [string]$record.source.tree -cne [string]$Candidate.source.tree -or
      [string]$record.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256) {
    throw "[$Code-candidate-binding]"
  }
  Assert-MIR42SealTargetSet -Rows @($record.targets) -Code $Code
  foreach ($candidateTarget in @($Candidate.targets)) {
    $row = @($record.targets | Where-Object { [string]$_.target -ceq [string]$candidateTarget.target })
    if ($row.Count -ne 1 -or [string]$row[0].distribution_version -cne [string]$candidateTarget.distribution_version -or
        [string]$row[0].archive.sha256 -cne [string]$candidateTarget.archive_sha256 -or
        [string]$row[0].archive.content_sha256 -cne [string]$candidateTarget.content_sha256 -or
        [int]$row[0].archive.entry_count -ne [int]$candidateTarget.entry_count -or
        [string]$row[0].status -cne 'passed') {
      throw "[$Code-target-binding] $([string]$candidateTarget.target)"
    }
  }
}

function Get-MIR42ExactQualificationReceipt {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate)
  $receipt = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-qualification'
  if ([string]$receipt.record.kind -cne 'MIR42FourTargetExactCandidateQualificationV1' -or
      [string]$receipt.record.status -cne 'MIR-4.2-FOUR-TARGET-EXACT-CANDIDATE-QUALIFICATION-PASSED-PRIVATE-UNSEALED' -or
      [string]$receipt.record.independent_verification -cne 'not-performed' -or
      [bool]$receipt.record.publication_authorized) {
    throw '[mir42-seal-qualification-state]'
  }
  Assert-MIR42ReceiptBinding -Receipt $receipt -Candidate $Candidate -Code 'mir42-seal-qualification'
  return $receipt
}

function Get-MIR42ExactIndependentVerificationReceipt {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Qualification)
  $receipt = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-independent'
  if ([string]$receipt.record.kind -cne 'MIR42FourTargetIndependentVerificationV1' -or
      [string]$receipt.record.status -cne 'MIR-4.2-FOUR-TARGET-INDEPENDENT-VERIFICATION-PASSED-PRIVATE-UNSEALED' -or
      [string]$receipt.record.qualification.sha256 -cne [string]$Qualification.sha256 -or
      [string]$receipt.record.qualification.record_sha256 -cne [string]$Qualification.record.record_sha256 -or
      [bool]$receipt.record.publication_authorized) {
    throw '[mir42-seal-independent-state]'
  }
  Assert-MIR42ReceiptBinding -Receipt $receipt -Candidate $Candidate -Code 'mir42-seal-independent'
  return $receipt
}

function Get-MIR42ProtectedSigningCeremony {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path)
  $receipt = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-signing'
  $schema = Join-Path $RepoRoot 'spec/schemas/mir4-protected-signing-ceremony-receipt-v1.schema.json'
  $raw = Get-Content -Raw -LiteralPath $receipt.path
  if (-not ($raw | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue)) { throw '[mir42-seal-signing-schema]' }
  if ([string]$receipt.record.status -cne 'accepted-protected-signing-authority' -or
      [string]$receipt.record.authorization.decision -cne 'AUTHORIZED' -or
      [bool]$receipt.record.secret_values_present) { throw '[mir42-seal-signing-state]' }
  $allowedPath = Join-Path $RepoRoot '.mir/releases/governance/mir4/allowed-signers.json'
  $allowed = Read-MIR42SealRecord -Path $allowedPath -Code 'mir42-seal-allowed-signers'
  $namespaces = @($allowed.record.rows | ForEach-Object { [string]$_.namespace } | Sort-Object -Unique)
  if ([string]$receipt.record.allowed_signers.record_sha256 -cne [string]$allowed.record.record_sha256 -or
      [string]$allowed.record.kind -cne 'MIR4AllowedSignersV1' -or [string]$allowed.record.state -ceq 'awaiting-protected-key' -or
      @($allowed.record.rows).Count -lt 3 -or (($namespaces -join '|') -cne 'mir4-ledger|mir4-source|mir4-target')) {
    throw '[mir42-seal-approved-signer-missing]'
  }
  return $receipt
}

function Get-MIR42SourceFreezeAuthority {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Signing)
  $authority = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-freeze'
  $record = $authority.record
  if ([string]$record.kind -cne 'MIR42SourceFreezeAuthorizationV1' -or
      [string]$record.status -cne 'MIR-4.2-SOURCE-FROZEN-AND-CANDIDATE-ALLOCATED' -or
      [string]$record.signing_ceremony.sha256 -cne [string]$Signing.sha256 -or
      [string]$record.signing_ceremony.record_sha256 -cne [string]$Signing.record.record_sha256 -or
      -not [bool]$record.ledger_signature.verified -or [string]$record.ledger_signature.namespace -cne 'mir4-ledger' -or
      -not [bool]$record.transition_gate.source_freeze -or -not [bool]$record.transition_gate.candidate_allocation -or
      -not [bool]$record.transition_gate.production_signing -or [bool]$record.transition_gate.technical_seal) {
    throw '[mir42-seal-freeze-authority-state]'
  }
  if ([string]$record.candidate_manifest.sha256 -cne [string]$Candidate.identity.sha256 -or
      [string]$record.candidate_manifest.record_sha256 -cne [string]$Candidate.identity.record.record_sha256 -or
      [string]$record.source.commit -cne [string]$Candidate.source.commit -or
      [string]$record.source.tree -cne [string]$Candidate.source.tree -or
      [string]$record.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256) {
    throw '[mir42-seal-freeze-authority-binding]'
  }
  return $authority
}

function Get-MIR42FourTargetTechnicalSealReadiness {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [string]$QualificationPath='',
    [string]$IndependentVerificationPath='',
    [string]$SigningCeremonyPath='',
    [string]$SourceFreezeAuthorityPath=''
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $checks = [ordered]@{}
  $blockers = [Collections.Generic.List[string]]::new()
  $state = [ordered]@{candidate=$null;qualification=$null;independent=$null;signing=$null;freeze=$null}
  try { $state.candidate = Get-MIR42ExactFourTargetCandidate -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath; $checks.candidate = $true } catch { $checks.candidate = $false; $blockers.Add($_.Exception.Message) }
  if ($checks.candidate -and -not [string]::IsNullOrWhiteSpace($QualificationPath)) { try { $state.qualification = Get-MIR42ExactQualificationReceipt -Path $QualificationPath -Candidate $state.candidate; $checks.qualification = $true } catch { $checks.qualification = $false; $blockers.Add($_.Exception.Message) } } else { $checks.qualification = $false; $blockers.Add('[mir42-seal-qualification-missing]') }
  if ($checks.qualification -and -not [string]::IsNullOrWhiteSpace($IndependentVerificationPath)) { try { $state.independent = Get-MIR42ExactIndependentVerificationReceipt -Path $IndependentVerificationPath -Candidate $state.candidate -Qualification $state.qualification; $checks.independent = $true } catch { $checks.independent = $false; $blockers.Add($_.Exception.Message) } } else { $checks.independent = $false; $blockers.Add('[mir42-seal-independent-missing]') }
  if (-not [string]::IsNullOrWhiteSpace($SigningCeremonyPath)) { try { $state.signing = Get-MIR42ProtectedSigningCeremony -RepoRoot $repo -Path $SigningCeremonyPath; $checks.signing = $true } catch { $checks.signing = $false; $blockers.Add($_.Exception.Message) } } else { $checks.signing = $false; $blockers.Add('[mir42-seal-signing-missing]') }
  if ($checks.candidate -and $checks.signing -and -not [string]::IsNullOrWhiteSpace($SourceFreezeAuthorityPath)) { try { $state.freeze = Get-MIR42SourceFreezeAuthority -Path $SourceFreezeAuthorityPath -Candidate $state.candidate -Signing $state.signing; $checks.freeze = $true } catch { $checks.freeze = $false; $blockers.Add($_.Exception.Message) } } else { $checks.freeze = $false; $blockers.Add('[mir42-seal-freeze-authority-missing]') }
  $ready = @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value }).Count -eq 0
  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42FourTargetTechnicalSealReadinessV1'
    status = if ($ready) { 'MIR-4.2-FOUR-TARGET-TECHNICAL-SEAL-READY' } else { 'MIR-4.2-FOUR-TARGET-TECHNICAL-SEAL-BLOCKED' }
    checks = [pscustomobject]$checks
    blockers = @($blockers | Select-Object -Unique)
    technical_seal_authorized = $ready
    protected_main_promotion_authorized = $false
    human_go_required_after_main_readback = $true
    tagging_authorized = $false
    publication_authorized = $false
    _state = [pscustomobject]$state
  }
}

function New-MIR42FourTargetTechnicalSeal {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [AllowEmptyString()][string]$QualificationPath='',
    [AllowEmptyString()][string]$IndependentVerificationPath='',
    [AllowEmptyString()][string]$SigningCeremonyPath='',
    [AllowEmptyString()][string]$SourceFreezeAuthorityPath='',
    [Parameter(Mandatory)][string]$OutputPath
  )
  $readiness = Get-MIR42FourTargetTechnicalSealReadiness -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath `
    -QualificationPath $QualificationPath -IndependentVerificationPath $IndependentVerificationPath `
    -SigningCeremonyPath $SigningCeremonyPath -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath
  if (-not [bool]$readiness.technical_seal_authorized) { throw "[mir42-seal-not-authorized] $($readiness.blockers -join '; ')" }
  $state = $readiness._state
  $seal = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42FourTargetTechnicalSealV1'
    status = 'MIR-4.2-FOUR-TARGET-TECHNICALLY-SEALED-AWAITING-PROTECTED-MAIN-PR'
    source = $state.candidate.source
    candidate_manifest = [ordered]@{sha256=[string]$state.candidate.identity.sha256;record_sha256=[string]$state.candidate.identity.record.record_sha256}
    qualification = [ordered]@{sha256=[string]$state.qualification.sha256;record_sha256=[string]$state.qualification.record.record_sha256}
    independent_verification = [ordered]@{sha256=[string]$state.independent.sha256;record_sha256=[string]$state.independent.record.record_sha256}
    signing_ceremony = [ordered]@{sha256=[string]$state.signing.sha256;record_sha256=[string]$state.signing.record.record_sha256}
    source_freeze_authority = [ordered]@{sha256=[string]$state.freeze.sha256;record_sha256=[string]$state.freeze.record.record_sha256}
    targets = @($state.candidate.targets)
    protected_main_promotion_authorized = $false
    human_go_required_after_main_readback = $true
    tagging_authorized = $false
    publication_authorized = $false
    record_sha256 = ''
  }
  $seal.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $seal
  Write-MIR4BootstrapRecord -Record $seal -Path $OutputPath | Out-Null
  return $seal
}
